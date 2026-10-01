import 'package:myshop/shared/widgets/app_button.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_assets.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/network/dio_interceptors.dart' show NetworkHealth;
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_freshness.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/presentation/main_navigation_shell.dart';

const _tag = 'BOOTSTRAP';

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

  Future<bool>? _queuePush;
  bool _running = false;
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
      } on ProviderNotFoundException {
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
            // Throws AuthException on 401/403; null means the server could
            // not be reached (offline / 5xx).
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
      // These don't depend on each other, so they run together (for an
      // employee, orders too).
      _SetupStep(
        title: 'Syncing organization details',
        errorText: "Couldn't sync organization details",
        parallelGroup: 1,
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
        parallelGroup: 1,
        hasCache: () => _localCache.getCachedProducts()?.isNotEmpty == true,
        run: () async => _posRepository.listProducts(),
      ),
      _SetupStep(
        title: 'Syncing payment methods',
        errorText: "Couldn't sync payment methods",
        parallelGroup: 1,
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
      if (isOwner && _ownerOutlets().length > 1)
        ..._ownerScopeSteps()
      else ...[
        _SetupStep(
          title: 'Syncing orders',
          errorText: "Couldn't sync orders",
          parallelGroup: 1,
          hasCache: () => _localCache.getCachedOrders() != null,
          isOrders: true,
          run: _ordersRepository.syncAllOrders,
        ),
        if (isOwner) ...[
          _SetupStep(
            title: 'Syncing dashboard',
            errorText: "Couldn't sync dashboard",
            parallelGroup: 2,
            hasCache: () => _localCache.getCachedDashboardMetrics() != null,
            run: () async => _ownerRepository.getDefaultDashboardMetrics(),
          ),
          _SetupStep(
            title: 'Syncing expenses',
            errorText: "Couldn't sync expenses",
            parallelGroup: 2,
            hasCache: () => _localCache.getCachedExpenses() != null,
            run: () async => _ownerRepository.listExpenses(),
          ),
        ],
      ],
      if (isOwner) ...[
        _SetupStep(
          title: 'Syncing staff',
          errorText: "Couldn't sync staff",
          parallelGroup: 2,
          hasCache: () => _localCache.getCachedStaff() != null,
          run: () async => _ownerRepository.listStaff(),
        ),
      ],
    ];
  }

  /// Outlets cached at sign-in (the login response caches every allowed
  /// outlet before this screen opens).
  List<Map<String, dynamic>> _ownerOutlets() =>
      _localCache.getAllowedOutlets() ?? const [];

  bool _scopeCached(String scope) {
    final all = scope == LocalCacheService.allScope;
    return _localCache.hasCachedOrdersFor(
          outletId: all ? null : scope,
          allOutlets: all,
        ) &&
        _localCache.getCachedDashboardMetricsForScope(scope) != null &&
        _localCache.getCachedExpensesForScope(scope) != null;
  }

  /// Owner with several outlets: one row for the combined "All outlets" view
  /// and one per outlet, each pulling orders, the default dashboard and
  /// expenses into that scope's own cache. A failed row does not stop the
  /// others — its Retry re-runs just that row.
  List<_SetupStep> _ownerScopeSteps() {
    final scopes = <(String, String)>[
      ('All outlets', LocalCacheService.allScope),
      for (final o in _ownerOutlets())
        (o['displayName']?.toString() ?? 'Outlet', o['id']?.toString() ?? ''),
    ].where((s) => s.$2.isNotEmpty).toList();
    return [
      for (var i = 0; i < scopes.length; i++)
        _SetupStep(
          title: 'Syncing ${scopes[i].$1}',
          errorText: "Couldn't sync ${scopes[i].$1}",
          subtitle: 'Orders, dashboard and expenses',
          continueOnError: true,
          parallelGroup: 2,
          hasCache: () => _scopeCached(scopes[i].$2),
          isOrders: true,
          run: () async {
            // Queued changes go up once, before any scope pulls. Only a
            // success is remembered, and a false result must not be pulled
            // over: unsent local changes would be overwritten.
            final pushed = await _pushQueueOnce();
            if (!pushed) {
              throw Exception('Unsent changes could not be uploaded yet');
            }
            await Future.wait([
              _ordersRepository.syncOrdersForScope(scopes[i].$2),
              _ownerRepository.syncDashboardForScope(scopes[i].$2),
              _ownerRepository.syncExpensesForScope(scopes[i].$2),
            ]);
          },
        ),
    ];
  }

  Future<bool> _pushQueueOnce() =>
      _queuePush ??= _ordersRepository.processPendingSyncQueue().then(
        (ok) {
          if (!ok) _queuePush = null;
          return ok;
        },
        onError: (Object e, StackTrace st) {
          _queuePush = null;
          Error.throwWithStackTrace(e, st);
        },
      );

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
  ///
  /// Consecutive rows sharing a `parallelGroup` run at the same time and the
  /// screen moves on once all of them have settled.
  Future<void> _runFrom(int index) async {
    // One run at a time: a Retry must not re-run rows the original loop is
    // still working on (it could also reach _finishAndNavigate twice).
    if (_running) return;
    _running = true;
    final failuresBefore = NetworkHealth.failures;
    try {
      await _runFromUnguarded(index, failuresBefore);
    } finally {
      _running = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _runFromUnguarded(int index, int failuresBefore) async {
    var i = index;
    while (i < _steps.length) {
      if (!mounted) return;
      final group = <int>[i];
      final g = _steps[i].parallelGroup;
      if (g != null) {
        while (i + group.length < _steps.length &&
            _steps[i + group.length].parallelGroup == g) {
          group.add(i + group.length);
        }
      }
      // A retry resumes at its own row; rows after it that already finished
      // (continue-on-error rows) are not redone.
      final toRun = [
        for (final j in group)
          if (j == index ||
              (_steps[j].status != StepStatus.done &&
                  _steps[j].status != StepStatus.offlineCached &&
                  _steps[j].status != StepStatus.active))
            j,
      ];
      final stops = await Future.wait(toRun.map(_runStep));
      if (!mounted || stops.any((stop) => stop)) return;
      i += group.length;
    }
    // Rows that failed but let the rest run still hold the user here, with
    // Retry on the row and "Continue anyway" below.
    if (_steps.any((s) => s.status == StepStatus.error)) return;
    // Repositories swallow network failures and serve their cache, so a
    // step can look "done" without ever reaching the server: only call the
    // phone fresh when no request failed during the run.
    if (!_isOffline &&
        NetworkHealth.failures == failuresBefore &&
        _steps.every((s) => s.status == StepStatus.done) &&
        !await _connectivityService.checkIsOffline()) {
      SyncFreshness.mark();
    }
    await _finishAndNavigate();
  }

  /// Runs one row. Returns true when the sequence should stop here (a failed
  /// row with nothing on the phone to fall back on, that isn't
  /// continue-on-error) or the screen is gone.
  Future<bool> _runStep(int i) async {
    final step = _steps[i];
    if (!mounted) return true;
    setState(() {
      step.status = StepStatus.active;
      step.error = null;
    });

    if (_isOffline && step.hasCache?.call() == true) {
      setState(() => step.status = StepStatus.offlineCached);
      return false;
    }

    final failuresBefore = NetworkHealth.failures;
    try {
      await step.run();
      if (!mounted) return true;
      // The repository may have caught a failure and returned its cache.
      final fellBack =
          NetworkHealth.failures != failuresBefore &&
          step.hasCache?.call() == true;
      setState(
        () =>
            step.status = fellBack ? StepStatus.offlineCached : StepStatus.done,
      );
    } catch (e, st) {
      AppLogger.log(
        _tag,
        'step "${step.title}" failed',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return true;
      if (e is AuthException && e.code == 'UNAUTHENTICATED') {
        // The session is dead: go to login through the session-revoked flow
        // rather than offering "Continue anyway".
        setState(() {
          step.status = StepStatus.error;
          step.error = step.errorText;
        });
        _dispatchSessionRevoked();
        return true;
      }
      if (e is AuthException) {
        // 403: the app-level handler decides (blocked screen / re-scope).
        setState(() {
          step.status = StepStatus.error;
          step.error = step.errorText;
        });
        return true;
      }
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
        return !step.continueOnError;
      }
    }
    return false;
  }

  void _dispatchSessionRevoked() {
    try {
      context.read<AuthBloc>().add(SessionRevokedEvent());
    } on ProviderNotFoundException catch (e) {
      AppLogger.log(_tag, 'no AuthBloc to report revoked session', error: e);
    }
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
    // Only an orders pull that really succeeded may mark the scope as
    // "no orders". Otherwise the scope stays uncached so the Orders screen
    // shows its "can't load" state instead of an empty list as truth (the
    // app shell skips this setup screen for the scope once it completes).
    final ordersPulled = _steps.any(
      (s) => s.isOrders && s.status == StepStatus.done,
    );
    if (ordersPulled && _localCache.getCachedOrders() == null) {
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
          onRetry: _running ? null : () => _runFrom(i),
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

  /// When this row fails, carry on with the rows after it instead of
  /// stopping here.
  final bool continueOnError;

  /// Consecutive rows with the same group run concurrently.
  final int? parallelGroup;

  /// Whether this row pulls the orders list of a scope.
  final bool isOrders;

  StepStatus status = StepStatus.pending;
  String? error;

  _SetupStep({
    required this.title,
    required this.errorText,
    this.subtitle,
    this.hasCache,
    this.continueOnError = false,
    this.parallelGroup,
    this.isOrders = false,
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
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(AppAssets.logo, width: 72, height: 72),
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
            TextActionButton(
              label: 'Retry',
              height: AppButtonHeight.compact,
              onPressed: onRetry,
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
