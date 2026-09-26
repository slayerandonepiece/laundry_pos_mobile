import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/presentation/main_navigation_shell.dart';

enum StepStatus { pending, active, done, error, offlineCached }

class BootstrapScreen extends StatefulWidget {
  final AuthenticatedState authState;
  final VoidCallback? onCompleted;
  final AuthRepository? authRepository;
  final PosRepository? posRepository;
  final OrdersRepository? ordersRepository;
  final OwnerRepository? ownerRepository;
  final LocalCacheService? localCache;
  final ConnectivityService? connectivityService;

  const BootstrapScreen({
    super.key,
    required this.authState,
    this.onCompleted,
    this.authRepository,
    this.posRepository,
    this.ordersRepository,
    this.ownerRepository,
    this.localCache,
    this.connectivityService,
  });

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  late final AuthRepository _authRepository;
  late final PosRepository _posRepository;
  late final OrdersRepository _ordersRepository;
  late final OwnerRepository _ownerRepository;
  late final LocalCacheService _localCache;
  late final ConnectivityService _connectivityService;

  late final List<_SetupStep> _steps;

  bool _isOffline = false;
  bool _canContinueAnyway = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? context.read<AuthRepository>();
    _posRepository = widget.posRepository ?? context.read<PosRepository>();
    _ordersRepository =
        widget.ordersRepository ?? context.read<OrdersRepository>();
    if (widget.ownerRepository != null) {
      _ownerRepository = widget.ownerRepository!;
    } else {
      try {
        _ownerRepository = context.read<OwnerRepository>();
      } catch (_) {
        _ownerRepository = OwnerRepository();
      }
    }
    _localCache = widget.localCache ?? LocalCacheService();
    _connectivityService =
        widget.connectivityService ?? ConnectivityService.instance;
    _isOffline = _connectivityService.isOffline;
    _steps = _buildSteps();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBootstrapSequence();
    });
  }

  /// Owner: organization & outlets, organization details, services &
  /// prices, payment methods, orders, dashboard, expenses, staff.
  /// Employee: their outlet, then organization details, services & prices,
  /// payment methods and orders for it (docs/OFFLINE-ID-SYNC-PLAN.md §4).
  List<_SetupStep> _buildSteps() {
    final isOwner = widget.authState.isOwner;
    final orgName = widget.authState.currentStore.storeName;
    return [
      if (isOwner)
        _SetupStep(
          title: 'Fetching organization & outlets',
          errorText: "Couldn't fetch organization & outlets",
          subtitle: orgName.isNotEmpty ? orgName : null,
          hasCache: () => _localCache.getAllowedOutlets() != null,
          run: () async {
            final outlets = await _authRepository.refreshOutletContext();
            if (outlets == null) throw Exception('No outlets returned');
          },
        )
      else
        _SetupStep(
          title: 'Opening your outlet',
          errorText: "Couldn't open your outlet",
          subtitle: _activeOutletName(),
          run: () async {},
        ),
      _SetupStep(
        title: 'Syncing organization details',
        errorText: "Couldn't sync organization details",
        hasCache: () =>
            (_localCache.getCachedStoreProfile() ??
                    _localCache.getCachedStoreDetails())
                ?.isNotEmpty ==
            true,
        run: () async => _authRepository.fetchStoreDetails(),
      ),
      _SetupStep(
        title: 'Syncing services & prices',
        errorText: "Couldn't sync services & prices",
        hasCache: () => _localCache.getCachedProducts()?.isNotEmpty == true,
        run: () async => _posRepository.listProducts(),
      ),
      _SetupStep(
        title: 'Syncing payment methods',
        errorText: "Couldn't sync payment methods",
        hasCache: () => _localCache.getCachedPaymentMethods() != null,
        run: () async {
          // listPaymentMethods() falls back to the cache instead of
          // throwing, so a failure shows up as nothing cached.
          await _posRepository.listPaymentMethods();
          if (_localCache.getCachedPaymentMethods() == null) {
            throw Exception('Payment methods not loaded');
          }
        },
      ),
      _SetupStep(
        title: 'Syncing orders',
        errorText: "Couldn't sync orders",
        hasCache: () => _localCache.getCachedOrders() != null,
        run: _ordersRepository.syncAllOrders,
      ),
      if (isOwner) ...[
        _SetupStep(
          title: 'Syncing dashboard',
          errorText: "Couldn't sync dashboard",
          hasCache: () => _localCache.getCachedDashboardMetrics() != null,
          run: () async => _ownerRepository.getDashboardMetrics(),
        ),
        _SetupStep(
          title: 'Syncing expenses',
          errorText: "Couldn't sync expenses",
          hasCache: () => _localCache.getCachedExpenses() != null,
          run: () async => _ownerRepository.listExpenses(),
        ),
        _SetupStep(
          title: 'Syncing staff',
          errorText: "Couldn't sync staff",
          hasCache: () => _localCache.getCachedStaff() != null,
          run: () async => _ownerRepository.listStaff(),
        ),
      ],
    ];
  }

  String? _activeOutletName() {
    final activeId = _localCache.getActiveOutletId();
    for (final outlet in _localCache.getAllowedOutlets() ?? const []) {
      if (outlet['id']?.toString() == activeId) {
        final name = outlet['displayName']?.toString() ?? '';
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  Future<void> _startBootstrapSequence() async {
    if (!mounted) return;

    // Check connectivity first: if offline, adapt behavior immediately
    final isOffline = await _connectivityService.checkIsOffline();
    if (!mounted) return;

    setState(() {
      _isOffline = isOffline;
    });

    await _runFrom(0);
  }

  /// Runs the steps from [index] on, in order. Offline with data already on
  /// the phone, a step uses it without a network call; a failed step with
  /// cached data falls back to it and carries on; a failed step without
  /// stops here with Retry (resumes from this step) and "Continue anyway".
  Future<void> _runFrom(int index) async {
    for (var i = index; i < _steps.length; i++) {
      if (!mounted) return;
      final step = _steps[i];
      setState(() {
        step.status = StepStatus.active;
        step.error = null;
      });

      if (_isOffline && step.hasCache?.call() == true) {
        setState(() => step.status = StepStatus.offlineCached);
        continue;
      }

      try {
        await step.run();
        if (!mounted) return;
        setState(() => step.status = StepStatus.done);
      } catch (_) {
        if (!mounted) return;
        if (step.hasCache?.call() == true) {
          setState(() {
            step.status = StepStatus.offlineCached;
            _canContinueAnyway = true;
          });
        } else {
          setState(() {
            step.status = StepStatus.error;
            step.error = step.errorText;
            _canContinueAnyway = true;
          });
          return;
        }
      }
    }
    await _finishAndNavigate();
  }

  bool get _allStepsCompleted => _steps.every(
    (s) => s.status == StepStatus.done || s.status == StepStatus.offlineCached,
  );

  Future<void> _finishAndNavigate() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    // Small delay so checkmark animation is visibly confirmed
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    if (widget.onCompleted != null) {
      widget.onCompleted!();
    } else {
      context.read<AuthBloc>().add(BootstrapCompletedEvent());
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigationShell()),
        );
      }
    }
  }

  Future<void> _continueAnyway() async {
    // An empty list marks this scope as set up, so the app doesn't route
    // straight back here; the Orders screen syncs an empty list itself.
    if (_localCache.getCachedOrders() == null) {
      await _localCache.setCachedOrders([]);
    }
    await _finishAndNavigate();
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      for (var i = 0; i < _steps.length; i++)
        _BootstrapStepItem(
          title: _steps[i].title,
          subtitle: _steps[i].subtitle,
          status: _steps[i].status,
          errorText: _steps[i].error,
          onRetry: () => _runFrom(i),
        ),
    ];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Spacer(flex: 2),

                        // Centered branding icon + top spinner / checkmark
                        _BootstrapHeader(allStepsCompleted: _allStepsCompleted),
                        const SizedBox(height: 18),

                        // Title & Subtitle
                        const Text(
                          'Setting things up',
                          style: AppTextStyles.h1,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isOffline
                              ? 'Offline · using data already on this phone'
                              : 'Just a moment while we sync your data',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.mutedText,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const Spacer(flex: 2),

                        // Checklist card
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.inset,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < steps.length; i++) ...[
                                if (i > 0)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 4),
                                    child: Divider(
                                      color: AppColors.divider,
                                      height: 1,
                                    ),
                                  ),
                                _ChecklistRow(
                                  title: steps[i].title,
                                  subtitle: steps[i].subtitle,
                                  status: steps[i].status,
                                  errorText: steps[i].errorText,
                                  onRetry: steps[i].onRetry,
                                ),
                              ],
                            ],
                          ),
                        ),

                        // "Continue anyway" escape hatch if error occurs but user shouldn't be trapped
                        if (_canContinueAnyway && !_allStepsCompleted) ...[
                          const SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: _continueAnyway,
                            icon: const Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            label: const Text(
                              'Continue anyway',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontBody,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],

                        const Spacer(flex: 3),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SetupStep {
  final String title;
  final String errorText;
  final String? subtitle;

  /// Whether usable data for this step is already on the phone.
  final bool Function()? hasCache;
  final Future<void> Function() run;

  StepStatus status = StepStatus.pending;
  String? error;

  _SetupStep({
    required this.title,
    required this.errorText,
    this.subtitle,
    this.hasCache,
    required this.run,
  });
}

class _BootstrapStepItem {
  final String title;
  final String? subtitle;
  final StepStatus status;
  final String? errorText;
  final VoidCallback? onRetry;

  const _BootstrapStepItem({
    required this.title,
    this.subtitle,
    required this.status,
    this.errorText,
    this.onRetry,
  });
}

class _BootstrapHeader extends StatelessWidget {
  final bool allStepsCompleted;

  const _BootstrapHeader({required this.allStepsCompleted});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Centered branding icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primaryTint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Icon(
              Icons.local_laundry_service_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Top spinner indicator / checkmark
        if (!allStepsCompleted)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          )
        else
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.successBg,
            ),
            child: const Center(
              child: Icon(Icons.check, size: 16, color: AppColors.success),
            ),
          ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final StepStatus status;
  final String? errorText;
  final VoidCallback? onRetry;

  const _ChecklistRow({
    required this.title,
    this.subtitle,
    required this.status,
    this.errorText,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _StepStatusIndicator(status: status),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: status == StepStatus.active
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: status == StepStatus.pending
                        ? AppColors.mutedText
                        : AppColors.text,
                  ),
                ),
                if (status == StepStatus.offlineCached)
                  Text(
                    'Using cached data',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11.5,
                      color: AppColors.faintText,
                    ),
                  )
                else if (subtitle != null && status == StepStatus.done)
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11.5,
                      color: AppColors.mutedText,
                    ),
                  )
                else if (errorText != null && status == StepStatus.error)
                  Text(
                    errorText!,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11.5,
                      color: AppColors.danger,
                    ),
                  ),
              ],
            ),
          ),
          if (status == StepStatus.error && onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                minimumSize: const Size(48, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepStatusIndicator extends StatelessWidget {
  final StepStatus status;

  const _StepStatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case StepStatus.pending:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.controlBorder, width: 2),
          ),
        );
      case StepStatus.active:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        );
      case StepStatus.done:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.successBg,
            border: Border.all(color: AppColors.success, width: 1.5),
          ),
          child: const Center(
            child: Icon(Icons.check, size: 14, color: AppColors.success),
          ),
        );
      case StepStatus.offlineCached:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.neutralBg,
            border: Border.all(
              color: AppColors.neutralText.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: const Center(
            child: Icon(Icons.check, size: 13, color: AppColors.neutralText),
          ),
        );
      case StepStatus.error:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.dangerBg,
            border: Border.all(color: AppColors.danger, width: 1.5),
          ),
          child: const Center(
            child: Icon(Icons.close, size: 13, color: AppColors.danger),
          ),
        );
    }
  }
}
