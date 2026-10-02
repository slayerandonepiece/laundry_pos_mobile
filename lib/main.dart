import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_environment.dart';
import 'package:myshop/core/gate/app_gate_service.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/network/firebase_service.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/app_resume_sync.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/theme/app_theme.dart';
import 'package:myshop/features/maintenance/presentation/maintenance_screen.dart';
import 'package:upgrader/upgrader.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/presentation/bootstrap_screen.dart';
import 'package:myshop/features/auth/presentation/login_screen.dart';
import 'package:myshop/features/auth/presentation/reset_password_screen.dart';
import 'package:myshop/features/auth/presentation/splash_screen.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/bloc/cart_event.dart';
import 'package:myshop/features/pos/bloc/cart_state.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/features/shell/presentation/main_navigation_shell.dart';
import 'package:myshop/features/shell/presentation/outlet_required_screen.dart';
import 'package:myshop/shared/widgets/blocked_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (Crashlytics, Analytics, Cloud Messaging, Remote Config)
  await FirebaseService.initialize();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.log(
      'FLUTTER_ERROR',
      '${details.exceptionAsString()}${details.stack != null ? '\n${details.stack}' : ''}',
      error: details.exception,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.log('PLATFORM_ERROR', '$error\n$stack', error: error);
    return true;
  };

  // Initialize Hive local cache (without adapters or code-gen)
  await LocalCacheService.init();

  final apiClient = ApiClient();
  final localCache = LocalCacheService();
  final secureStorage = SecureStorageService();

  final authRepository = AuthRepository(
    apiClient: apiClient,
    localCache: localCache,
    secureStorage: secureStorage,
  );
  final posRepository = PosRepository(
    apiClient: apiClient,
    localCache: localCache,
  );
  final ordersRepository = OrdersRepository(apiClient: apiClient);
  final ownerRepository = OwnerRepository(apiClient: apiClient);

  runApp(
    MyShopApp(
      apiClient: apiClient,
      authRepository: authRepository,
      posRepository: posRepository,
      ordersRepository: ordersRepository,
      ownerRepository: ownerRepository,
      localCache: localCache,
    ),
  );
}

enum OutletAccessResolution { signOut, outletRevoked, keepSignedIn }

/// Decides what a reason-less 403 / "Invalid outlet" means. Only a real
/// 401/403 from the server (or an outlet that is still allowed, i.e. the 403
/// was not about outlet scope) signs the user out; a network/5xx failure of
/// the refresh keeps them signed in.
Future<OutletAccessResolution> resolveOutletAccessLost({
  required String? previousOutletId,
  required Future<List<Map<String, dynamic>>?> Function() refresh,
}) async {
  if (previousOutletId == null) return OutletAccessResolution.signOut;
  try {
    final fresh = await refresh();
    if (fresh == null) return OutletAccessResolution.keepSignedIn;
    if (fresh.any((o) => o['id']?.toString() == previousOutletId)) {
      return OutletAccessResolution.signOut;
    }
    return OutletAccessResolution.outletRevoked;
  } on AuthException {
    return OutletAccessResolution.signOut;
  }
}

class MyShopApp extends StatefulWidget {
  final ApiClient apiClient;
  final AuthRepository authRepository;
  final PosRepository posRepository;
  final OrdersRepository ordersRepository;
  final OwnerRepository ownerRepository;
  final LocalCacheService localCache;

  const MyShopApp({
    super.key,
    required this.apiClient,
    required this.authRepository,
    required this.posRepository,
    required this.ordersRepository,
    required this.ownerRepository,
    required this.localCache,
  });

  @override
  State<MyShopApp> createState() => _MyShopAppState();
}

class _MyShopAppState extends State<MyShopApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _rescoping = false;
  late bool _splashAnimationCompleted = WidgetsBinding.instance.runtimeType
      .toString()
      .contains('Test');

  bool _isMaintenanceMode = false;
  bool _isIosForceUpdateRequired = false;
  GateDecision? _deferredGateDecision;
  late final Upgrader _upgrader;

  late final AuthBloc _authBloc;
  late final OutletScopeCubit _outletScopeCubit;
  late final CartBloc _cartBloc;
  late final OrdersBloc _ordersBloc;
  late final OwnerBloc _ownerBloc;
  late final AppResumeSync _appResumeSync;

  /// The setup (syncing) screen runs on a fresh login and when the active
  /// outlet scope has never been synced to this phone (no cached order
  /// list yet — e.g. switching to a new outlet). Cold start otherwise opens
  /// straight from local data.
  bool _needsSetup(AuthenticatedState state) =>
      state.isFreshLogin ||
      (widget.localCache.getCachedOrders() == null &&
          _setupSkippedScope != _scopeKey());

  /// Scope whose setup screen the user left via "Continue anyway" with no
  /// orders pulled. It stays uncached (Orders shows "can't load") but must
  /// not trap the user on the setup screen.
  String? _setupSkippedScope;

  String? _scopeKey() {
    final scope = _outletScopeCubit.state;
    return scope.allOutlets ? 'all' : scope.activeOutletId;
  }

  Future<void> _handleOutletAccessLost() async {
    if (_rescoping) return;
    _rescoping = true;
    try {
      final previous = widget.localCache.getActiveOutletId();
      String? previousName;
      if (previous != null) {
        for (final outlet in _outletScopeCubit.state.allowed) {
          if (outlet.id == previous) {
            previousName = outlet.displayName;
            break;
          }
        }
      }
      if (previous == null) {
        _authBloc.add(AccessForbiddenEvent());
        return;
      }
      final resolution = await resolveOutletAccessLost(
        previousOutletId: previous,
        refresh: widget.authRepository.refreshOutletContext,
      );
      if (resolution == OutletAccessResolution.keepSignedIn) {
        // Could not reach the server (offline / 5xx): that says nothing about
        // access, so keep the user signed in with the cached outlets.
        AppLogger.log('MAIN', 'outlet refresh inconclusive; staying signed in');
        return;
      }
      if (resolution == OutletAccessResolution.signOut) {
        _authBloc.add(AccessForbiddenEvent());
        return;
      }
      // Outlet genuinely revoked/invalid:
      _cartBloc.add(ResetSaleEvent());
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
      _outletScopeCubit.clearSelection();
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            previousName != null
                ? 'You no longer have access to $previousName. Choose another outlet.'
                : 'Your outlet access changed. Choose another outlet.',
          ),
        ),
      );
    } finally {
      _rescoping = false;
    }
  }

  Future<void> _evaluateStartupGate() async {
    final decision = await AppGateService.evaluateGate();
    if (!mounted) return;
    _applyGateDecision(decision);
  }

  void _applyGateDecision(GateDecision decision) {
    switch (decision) {
      case GateDecision.maintenance:
        if (!_isMaintenanceMode) {
          setState(() => _isMaintenanceMode = true);
        }
        break;
      case GateDecision.androidForceUpdate:
        AppGateService.performAndroidForceUpdateIfNeeded();
        break;
      case GateDecision.iosForceUpdate:
        if (!_isIosForceUpdateRequired) {
          setState(() => _isIosForceUpdateRequired = true);
        }
        break;
      case GateDecision.proceed:
        if (_isMaintenanceMode || _isIosForceUpdateRequired) {
          setState(() {
            _isMaintenanceMode = false;
            _isIosForceUpdateRequired = false;
          });
        }
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _handleAppResume();
    }
  }

  Future<void> _handleAppResume() async {
    // Pick up subscription, access and password-change changes made while the
    // app was in the background. Silent: no loading screen, no sign-out when
    // offline.
    if (_authBloc.state is AuthenticatedState) {
      _authBloc.add(RefreshAuthStatusEvent());
    }
    await FirebaseService.refreshRemoteConfig();
    final decision = await AppGateService.evaluateGate();
    if (!mounted) return;

    if (decision == GateDecision.proceed) {
      _deferredGateDecision = null;
      if (_isMaintenanceMode || _isIosForceUpdateRequired) {
        setState(() {
          _isMaintenanceMode = false;
          _isIosForceUpdateRequired = false;
        });
      }
      return;
    }

    // A blocking condition (maintenance or force-update) was detected!
    final midTx = AppGateService.isMidTransaction(
      cartState: _cartBloc.state,
      ordersState: _ordersBloc.state,
    );

    if (midTx) {
      AppLogger.log(
        'APP_GATE',
        'Resume gate triggered $decision while mid-transaction; deferring until safe screen.',
      );
      _deferredGateDecision = decision;
    } else {
      _deferredGateDecision = null;
      _applyGateDecision(decision);
    }
  }

  void _checkDeferredGate() {
    if (_deferredGateDecision == null) return;
    final midTx = AppGateService.isMidTransaction(
      cartState: _cartBloc.state,
      ordersState: _ordersBloc.state,
    );
    if (!midTx) {
      final decision = _deferredGateDecision!;
      _deferredGateDecision = null;
      AppLogger.log(
        'APP_GATE',
        'Transaction concluded; applying deferred gate decision: $decision',
      );
      _applyGateDecision(decision);
    }
  }

  Future<void> _handleCheckAgain() async {
    await FirebaseService.refreshRemoteConfig();
    final decision = await AppGateService.evaluateGate();
    if (!mounted) return;
    if (decision == GateDecision.proceed) {
      setState(() {
        _isMaintenanceMode = false;
        _isIosForceUpdateRequired = false;
        _deferredGateDecision = null;
      });
    } else {
      _applyGateDecision(decision);
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Maintenance is still in progress. Please check again shortly.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _wrapWithUpgradeAlertIfNeeded(Widget child) {
    if (_isIosForceUpdateRequired) {
      return UpgradeAlert(
        upgrader: _upgrader,
        navigatorKey: _navigatorKey,
        barrierDismissible: false,
        shouldPopScope: () => false,
        showIgnore: false,
        showLater: false,
        child: child,
      );
    }
    return child;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _upgrader = AppGateService.createUpgrader();
    _evaluateStartupGate();

    ConnectivityService.instance.start();
    _appResumeSync = AppResumeSync();

    _authBloc = AuthBloc(
      authRepository: widget.authRepository,
      localCache: widget.localCache,
    )..add(CheckAuthStatusEvent());

    _outletScopeCubit = OutletScopeCubit(localCache: widget.localCache);

    _cartBloc = CartBloc(posRepository: widget.posRepository);

    _ordersBloc = OrdersBloc(ordersRepository: widget.ordersRepository);

    _ownerBloc = OwnerBloc(ownerRepository: widget.ownerRepository);

    // Automatic 401 handling: session revocation triggers immediate sign-out
    widget.apiClient.onUnauthorized = () {
      if (_authBloc.state is AuthenticatedState) {
        _authBloc.add(SessionRevokedEvent());
      }
    };

    // Automatic 403 handling: access denial triggers blocked screen live,
    // or re-scopes the outlet when a reason-less 403 reflects lost outlet access.
    widget.apiClient.onForbidden = (reason, paidThroughDate) {
      if (_authBloc.state is AuthenticatedState) {
        if (reason == null || reason.isEmpty) {
          _handleOutletAccessLost();
        } else {
          _authBloc.add(
            AccessForbiddenEvent(
              reason: reason,
              paidThroughDate: paidThroughDate,
            ),
          );
        }
      }
    };

    widget.apiClient.onInvalidOutlet = () {
      if (_authBloc.state is AuthenticatedState) {
        _handleOutletAccessLost();
      }
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appResumeSync.dispose();
    ConnectivityService.instance.dispose();
    _authBloc.close();
    _outletScopeCubit.close();
    _cartBloc.close();
    _ordersBloc.close();
    _ownerBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: widget.authRepository),
        RepositoryProvider<PosRepository>.value(value: widget.posRepository),
        RepositoryProvider<OrdersRepository>.value(
          value: widget.ordersRepository,
        ),
        RepositoryProvider<OwnerRepository>.value(
          value: widget.ownerRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: _authBloc),
          BlocProvider<OutletScopeCubit>.value(value: _outletScopeCubit),
          BlocProvider<CartBloc>.value(value: _cartBloc),
          BlocProvider<OrdersBloc>.value(value: _ordersBloc),
          BlocProvider<OwnerBloc>.value(value: _ownerBloc),
        ],
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
          title: AppEnvironmentConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.theme,
          home: _isMaintenanceMode
              ? MaintenanceScreen(
                  message: FirebaseService.maintenanceMessage,
                  eta: FirebaseService.maintenanceEta,
                  onCheckAgain: _handleCheckAgain,
                )
              : _wrapWithUpgradeAlertIfNeeded(
                  MultiBlocListener(
                    listeners: [
                      BlocListener<CartBloc, CartState>(
                        listener: (context, state) => _checkDeferredGate(),
                      ),
                      BlocListener<OrdersBloc, OrdersState>(
                        listener: (context, state) => _checkDeferredGate(),
                      ),
                      BlocListener<AuthBloc, AuthState>(
                        listener: (context, state) {
                          if (state is UnauthenticatedState) {
                            _outletScopeCubit.reset();
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          } else if (state is AuthenticatedState) {
                            if (state.isFreshLogin) {
                              // Resolve the O3 initial outlet scope before
                              // BootstrapScreen (which fetches orders directly) ever
                              // mounts — otherwise an employee who hasn't picked an
                              // outlet yet 403s immediately.
                              _outletScopeCubit.adoptFromLogin(
                                isOwner: state.isOwner,
                              );
                              if (_outletScopeCubit.state.missingCache) {
                                _authBloc.add(SessionRevokedEvent());
                              }
                              return;
                            }

                            // Cold start (or post-bootstrap re-entry): re-read
                            // whatever outlet scope is already cached. Preloading
                            // catalog/orders/dashboard itself happens in the
                            // OutletScopeCubit listener below, once scope is
                            // actually resolved — that also covers the case where a
                            // cold-start employee has to pick from
                            // OutletRequiredScreen first.
                            _outletScopeCubit.hydrate();
                            if (_outletScopeCubit.state.missingCache) {
                              _authBloc.add(SessionRevokedEvent());
                            }
                          }
                        },
                      ),
                      BlocListener<OutletScopeCubit, OutletScope>(
                        listener: (context, scope) {
                          final authState = _authBloc.state;
                          if (authState is! AuthenticatedState ||
                              _needsSetup(authState)) {
                            // Fresh-login / new-outlet preload is BootstrapScreen's
                            // job, not OrdersBloc/CartBloc's — see the listener above.
                            return;
                          }
                          if (!scope.missingCache &&
                              !scope.requiresSelection &&
                              !scope.blockedNoOutlet) {
                            _cartBloc.add(LoadCatalogEvent());
                            _ordersBloc.add(LoadOrdersEvent());
                            if (authState.isOwner) {
                              _ownerBloc.add(LoadDashboardEvent());
                              _ownerBloc.add(LoadExpensesEvent());
                            }
                          }
                        },
                      ),
                    ],
                    child: BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final showSplash =
                            !_splashAnimationCompleted ||
                            state is AuthInitialState ||
                            (state is AuthLoadingState && state.isInitialCheck);

                        if (showSplash) {
                          return SplashScreen(
                            onAnimationComplete: () {
                              if (mounted && !_splashAnimationCompleted) {
                                setState(() {
                                  _splashAnimationCompleted = true;
                                });
                              }
                            },
                          );
                        }

                        if (state is MustChangePasswordState ||
                            (state is AuthLoadingState &&
                                state.message == 'Updating password...')) {
                          return const ResetPasswordScreen();
                        }

                        if (state is AccessBlockedState) {
                          return BlockedScreen(
                            reason: state.reason,
                            isOwner: state.isOwner,
                            paidThroughDate: state.paidThroughDate,
                            ownerPhone: state.ownerPhone,
                            onRetry: () {
                              _authBloc.add(CheckAuthStatusEvent());
                            },
                            onSignOut: () {
                              _authBloc.add(LogoutRequestedEvent());
                            },
                            pendingCount: widget.localCache
                                .getTotalPendingCount(),
                          );
                        }

                        if (state is AuthenticatedState) {
                          return BlocBuilder<OutletScopeCubit, OutletScope>(
                            builder: (context, scope) {
                              if (scope.missingCache) {
                                // SessionRevokedEvent was just dispatched from the
                                // listener above; show a brief transitional splash
                                // rather than guessing an outlet.
                                return const SplashScreen(animate: false);
                              }

                              if (scope.blockedNoOutlet) {
                                return BlockedScreen(
                                  reason: 'no_outlet_assigned',
                                  isOwner: false,
                                  onRetry: () {
                                    _authBloc.add(CheckAuthStatusEvent());
                                  },
                                  onSignOut: () {
                                    _authBloc.add(LogoutRequestedEvent());
                                  },
                                  pendingCount: widget.localCache
                                      .getTotalPendingCount(),
                                );
                              }

                              if (scope.requiresSelection) {
                                return OutletRequiredScreen(
                                  outlets: scope.allowed,
                                  onSelected: (outletId) {
                                    _outletScopeCubit.select(outletId);
                                  },
                                );
                              }

                              if (_needsSetup(state)) {
                                return BootstrapScreen(
                                  // A new scope (outlet switch) restarts the setup.
                                  key: ValueKey(
                                    scope.allOutlets
                                        ? 'all'
                                        : scope.activeOutletId,
                                  ),
                                  authState: state,
                                  authRepository: widget.authRepository,
                                  posRepository: widget.posRepository,
                                  ordersRepository: widget.ordersRepository,
                                  ownerRepository: widget.ownerRepository,
                                  localCache: widget.localCache,
                                  onCompleted: () {
                                    _setupSkippedScope = _scopeKey();
                                    _authBloc.add(BootstrapCompletedEvent());
                                  },
                                );
                              }
                              return const MainNavigationShell();
                            },
                          );
                        }

                        // Default: UnauthenticatedState or AuthLoadingState (when signing in)
                        return const LoginScreen();
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
