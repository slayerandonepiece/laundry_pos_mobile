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
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/presentation/main_navigation_shell.dart';

enum StepStatus { pending, active, done, error, offlineCached }

class EmployeeBootstrapScreen extends StatefulWidget {
  final AuthenticatedState authState;
  final VoidCallback? onCompleted;
  final AuthRepository? authRepository;
  final PosRepository? posRepository;
  final OrdersRepository? ordersRepository;
  final LocalCacheService? localCache;
  final ConnectivityService? connectivityService;

  const EmployeeBootstrapScreen({
    super.key,
    required this.authState,
    this.onCompleted,
    this.authRepository,
    this.posRepository,
    this.ordersRepository,
    this.localCache,
    this.connectivityService,
  });

  @override
  State<EmployeeBootstrapScreen> createState() =>
      _EmployeeBootstrapScreenState();
}

class _EmployeeBootstrapScreenState extends State<EmployeeBootstrapScreen> {
  late final AuthRepository _authRepository;
  late final PosRepository _posRepository;
  late final OrdersRepository _ordersRepository;
  late final LocalCacheService _localCache;
  late final ConnectivityService _connectivityService;

  StepStatus _step1Status = StepStatus.pending;
  StepStatus _step2Status = StepStatus.pending;
  StepStatus _step3Status = StepStatus.pending;
  StepStatus _step4Status = StepStatus.pending;

  String? _step2Error;
  String? _step3Error;
  String? _step4Error;

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
    _localCache = widget.localCache ?? LocalCacheService();
    _connectivityService =
        widget.connectivityService ?? ConnectivityService.instance;
    _isOffline = _connectivityService.isOffline;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBootstrapSequence();
    });
  }

  Future<void> _startBootstrapSequence() async {
    if (!mounted) return;

    // Check connectivity first: if offline, adapt behavior immediately
    final isOffline = await _connectivityService.checkIsOffline();
    if (!mounted) return;

    setState(() {
      _isOffline = isOffline;
    });

    // Step 1: Finding your store (instant from AuthenticatedState.currentStore)
    setState(() {
      _step1Status = StepStatus.active;
    });
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() {
      _step1Status = StepStatus.done;
    });

    // Run remaining steps sequentially
    await _executeStep2();
  }

  // Step 2: Loading store details (GET /api/v1/profile)
  Future<void> _executeStep2() async {
    if (!mounted) return;
    setState(() {
      _step2Status = StepStatus.active;
      _step2Error = null;
    });

    if (_isOffline) {
      final cached =
          _localCache.getCachedStoreProfile() ??
          _localCache.getCachedStoreDetails();
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _step2Status = StepStatus.offlineCached;
        });
        await _executeStep3();
        return;
      }
    }

    try {
      await _authRepository.fetchStoreDetails();
      if (!mounted) return;
      setState(() {
        _step2Status = StepStatus.done;
      });
      await _executeStep3();
    } catch (e) {
      if (!mounted) return;
      // Best effort check if cached store details are available
      final cached =
          _localCache.getCachedStoreProfile() ??
          _localCache.getCachedStoreDetails();
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _step2Status = StepStatus.offlineCached;
          _canContinueAnyway = true;
        });
        await _executeStep3();
      } else {
        setState(() {
          _step2Status = StepStatus.error;
          _step2Error = 'Failed to load store details';
          _canContinueAnyway = true;
        });
      }
    }
  }

  // Step 3: Loading products (PosRepository.listProducts)
  Future<void> _executeStep3() async {
    if (!mounted) return;
    setState(() {
      _step3Status = StepStatus.active;
      _step3Error = null;
    });

    if (_isOffline) {
      final cached = _localCache.getCachedProducts();
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _step3Status = StepStatus.offlineCached;
        });
        await _executeStep4();
        return;
      }
    }

    try {
      await _posRepository.listProducts();
      if (!mounted) return;
      setState(() {
        _step3Status = StepStatus.done;
      });
      await _executeStep4();
    } catch (e) {
      if (!mounted) return;
      final cached = _localCache.getCachedProducts();
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _step3Status = StepStatus.offlineCached;
          _canContinueAnyway = true;
        });
        await _executeStep4();
      } else {
        setState(() {
          _step3Status = StepStatus.error;
          _step3Error = 'Failed to load products';
          _canContinueAnyway = true;
        });
      }
    }
  }

  // Step 4: Loading recent orders (GET /api/v1/orders?limit=30&sort=recent)
  Future<void> _executeStep4() async {
    if (!mounted) return;
    setState(() {
      _step4Status = StepStatus.active;
      _step4Error = null;
    });

    if (_isOffline) {
      final cached = _localCache.getCachedOrders();
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _step4Status = StepStatus.offlineCached;
        });
        await _finishAndNavigate();
        return;
      }
    }

    try {
      await _ordersRepository.fetchRecentOrders(limit: 30, sort: 'recent');
      if (!mounted) return;
      setState(() {
        _step4Status = StepStatus.done;
      });
      await _finishAndNavigate();
    } catch (e) {
      if (!mounted) return;
      final cached = _localCache.getCachedOrders();
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _step4Status = StepStatus.offlineCached;
          _canContinueAnyway = true;
        });
        await _finishAndNavigate();
      } else {
        setState(() {
          _step4Status = StepStatus.error;
          _step4Error = 'Failed to load orders';
          _canContinueAnyway = true;
        });
      }
    }
  }

  bool get _allStepsCompleted {
    return (_step1Status == StepStatus.done) &&
        (_step2Status == StepStatus.done ||
            _step2Status == StepStatus.offlineCached) &&
        (_step3Status == StepStatus.done ||
            _step3Status == StepStatus.offlineCached) &&
        (_step4Status == StepStatus.done ||
            _step4Status == StepStatus.offlineCached);
  }

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

  void _continueAnyway() {
    _finishAndNavigate();
  }

  @override
  Widget build(BuildContext context) {
    final storeName = widget.authState.currentStore.storeName;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

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

                // Top spinner indicator
                if (!_allStepsCompleted)
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
                      child: Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.success,
                      ),
                    ),
                  ),
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
                      ? 'Offline · getting store ready from cached data'
                      : 'Just a moment while we get your store ready',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.mutedText,
                  ),
                  textAlign: TextAlign.center,
                ),

                const Spacer(flex: 2),

                // 4-row checklist card
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
                      _buildChecklistRow(
                        title: 'Finding your store',
                        subtitle: storeName.isNotEmpty ? storeName : null,
                        status: _step1Status,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Divider(color: AppColors.divider, height: 1),
                      ),
                      _buildChecklistRow(
                        title: 'Loading store details',
                        status: _step2Status,
                        errorText: _step2Error,
                        onRetry: _executeStep2,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Divider(color: AppColors.divider, height: 1),
                      ),
                      _buildChecklistRow(
                        title: 'Loading products',
                        status: _step3Status,
                        errorText: _step3Error,
                        onRetry: _executeStep3,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Divider(color: AppColors.divider, height: 1),
                      ),
                      _buildChecklistRow(
                        title: 'Loading recent orders',
                        status: _step4Status,
                        errorText: _step4Error,
                        onRetry: _executeStep4,
                      ),
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
      ),
    );
  }

  Widget _buildChecklistRow({
    required String title,
    String? subtitle,
    required StepStatus status,
    String? errorText,
    VoidCallback? onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildStatusIndicator(status),
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
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11.5,
                      color: AppColors.mutedText,
                    ),
                  )
                else if (errorText != null && status == StepStatus.error)
                  Text(
                    errorText,
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

  Widget _buildStatusIndicator(StepStatus status) {
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
