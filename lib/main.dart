import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:in_app_update_flutter/in_app_update_flutter.dart';
import 'package:firebase_analytics/observer.dart';
import 'package:myshop/core/analytics/app_analytics.dart';
import 'package:myshop/core/constants/app_environment.dart';
import 'package:myshop/core/error/crash_context.dart';
import 'package:myshop/core/error/error_reporting.dart';
import 'package:myshop/core/gate/app_gate_service.dart';
import 'package:myshop/core/gate/update_advisory.dart';
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
import 'package:myshop/features/update/presentation/update_required_screen.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/presentation/bootstrap_screen.dart';
import 'package:myshop/features/auth/presentation/login_screen.dart';
import 'package:myshop/features/auth/presentation/account_restore_screen.dart';
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

void main() {
  // Startup and runApp share one guarded zone: an error anywhere in startup,
  // or an uncaught async error later, is reported instead of lost.
  ErrorReporting.runGuarded(_start);
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (Crashlytics, Analytics, Cloud Messaging, Remote Config)
  await FirebaseService.initialize();

  // After Firebase, and never overwritten later: Flutter, platform and isolate
  // errors all end up in Crashlytics as fatal in non-debug builds.
  ErrorReporting.install();

  // Initialize Hive local cache (without adapters or code-gen)
  await LocalCacheService.init();

  // Requests report the installed version so the backend can advise updates.
  await UpdateAdvisory.init();

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

/// Re-checks the update prompt whenever a screen closes, so a prompt held back
/// because a form was open appears as soon as the user is back on the shell.
class _UpdateRetryObserver extends NavigatorObserver {
  _UpdateRetryObserver(this.onSettled);

  final VoidCallback onSettled;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onSettled();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onSettled();
}

class _MyShopAppState extends State<MyShopApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _rescoping = false;
  bool _hasAuthenticatedContext = false;
  late bool _splashAnimationCompleted = WidgetsBinding.instance.runtimeType
      .toString()
      .contains('Test');

  bool _isMaintenanceMode = false;
  bool _isIosForceUpdateRequired = false;
  GateDecision? _deferredGateDecision;

  // Backend-advertised update prompt (see UpdateAdvisory). Soft is offered once
  // per launch, urgent once per foreground session; both wait for a safe moment.
  bool _updateFlowActive = false;
  bool _softUpdateOffered = false;
  bool _urgentUpdateOffered = false;
  // iOS mandatory update: the blocker overlays the app while this is true.
  bool _iosUrgentBlocker = false;
  DateTime? _softRetryAt;
  Timer? _blockerRecheck;
  StreamSubscription<InstallStateAndroid>? _installSub;
  late final _updateRetryObserver = _UpdateRetryObserver(
    () => WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyUpdateAdvisory();
    }),
  );

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
      _urgentUpdateOffered = false;
      _handleAppResume();
      _applyUpdateAdvisory();
      if (_iosUrgentBlocker) UpdateAdvisory.probe();
    }
  }

  /// Offers the update the backend advertised, but only when no sale is in
  /// progress. Retried from the cart/orders listeners until a safe moment.
  void _applyUpdateAdvisory() {
    if (!mounted || kIsWeb) return;
    // The backend's level, double-checked against the installed version: an
    // install already at or above the minimum is never blocked or prompted.
    final level = UpdateAdvisory.effective;
    if (_iosUrgentBlocker && level != UpdateLevel.urgent) {
      // The backend lowered the level: never leave the user stuck behind it.
      setState(() => _iosUrgentBlocker = false);
    }
    if (level == UpdateLevel.none) {
      _softUpdateOffered = false;
      _urgentUpdateOffered = false;
      _softRetryAt = null;
    }
    final offer = UpdateAdvisory.nextOffer(
      level: level,
      flowActive: _updateFlowActive,
      softOffered: _softUpdateOffered || _softRetryPending,
      urgentOffered: Platform.isIOS ? _iosUrgentBlocker : _urgentUpdateOffered,
      safeMoment: _isSafeForUpdatePrompt(),
    );
    if (offer == null) return;
    if (offer == UpdateLevel.soft) {
      _softUpdateOffered = true;
    } else if (!Platform.isIOS) {
      _urgentUpdateOffered = true;
    }
    _offerUpdate(offer);
  }

  /// Safe = no sale in progress and no screen pushed over the main shell, so
  /// the prompt never lands on a half-filled form. Retried when the user
  /// returns (see [_UpdateRetryObserver]).
  bool _isSafeForUpdatePrompt() =>
      _navigatorKey.currentState?.canPop() != true &&
      !AppGateService.isMidTransaction(
        cartState: _cartBloc.state,
        ordersState: _ordersBloc.state,
      );

  Future<void> _offerUpdate(UpdateLevel level) async {
    if (kIsWeb) return;
    _updateFlowActive = true;
    try {
      if (Platform.isAndroid) {
        if (level == UpdateLevel.soft) _watchFlexibleUpdate();
        await AppGateService.startAndroidUpdate(
          immediate: level == UpdateLevel.urgent,
        );
      } else if (Platform.isIOS) {
        if (level == UpdateLevel.soft) {
          await _offerIosSoftUpdate();
        } else if (FirebaseService.iosAppStoreId.trim().isNotEmpty) {
          // Without a store ID there is nowhere to send the user: fail open
          // instead of blocking behind a button that cannot work.
          setState(() => _iosUrgentBlocker = true);
        }
      }
    } finally {
      _updateFlowActive = false;
    }
  }

  /// A flexible update downloads in the background; offer the restart once done.
  void _watchFlexibleUpdate() {
    _installSub ??= AppGateService.androidInstallState.listen((state) {
      if (state.status != InstallStatusAndroid.downloaded) return;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: const Text('Update downloaded.'),
          duration: const Duration(days: 1),
          action: SnackBarAction(
            label: 'Restart',
            onPressed: AppGateService.completeAndroidUpdate,
          ),
        ),
      );
    });
  }

  bool get _softRetryPending {
    final at = _softRetryAt;
    return at != null && DateTime.now().isBefore(at);
  }

  /// Apple's own App Store sheet, on top of everything; the user can close it.
  /// Needs a connection, so without one (or if the sheet fails) the prompt is
  /// tried again a couple of minutes later instead of being lost for the launch.
  Future<void> _offerIosSoftUpdate() async {
    if (FirebaseService.iosAppStoreId.trim().isEmpty) return;
    final online = !await ConnectivityService.instance.checkIsOffline();
    final shown = online && await AppGateService.showIosUpdateSheet();
    if (!shown) {
      _softUpdateOffered = false;
      _softRetryAt = DateTime.now().add(const Duration(minutes: 2));
    }
  }

  /// Update now: check the connection first, then open Apple's App Store
  /// sheet, falling back to the listing itself.
  Future<UpdateAttempt> _openIosUpdate() async {
    if (await ConnectivityService.instance.checkIsOffline()) {
      return UpdateAttempt.offline;
    }
    var opened = await AppGateService.showIosUpdateSheet();
    if (!opened) opened = await AppGateService.openAppStorePage();
    // Back from the App Store: re-check against the installed version.
    if (mounted) _applyUpdateAdvisory();
    return opened ? UpdateAttempt.opened : UpdateAttempt.failed;
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
    _applyUpdateAdvisory();
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

  /// Keeps the app mounted (listeners, tab state) and covers it with the
  /// mandatory-update screen. Set by the backend level or, as a fallback when
  /// the backend sends none, by the Remote Config gate.
  Widget _wrapWithUpdateBlocker(Widget child) {
    if (!_isIosForceUpdateRequired && !_iosUrgentBlocker) return child;
    return Stack(
      children: [
        ExcludeSemantics(child: child),
        Positioned.fill(child: UpdateRequiredScreen(onUpdate: _openIosUpdate)),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _evaluateStartupGate();
    // While the mandatory-update page is up the app may be idle (even signed
    // out), so nothing else would tell it the level was lowered: ask now and then.
    _blockerRecheck = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_iosUrgentBlocker) UpdateAdvisory.probe();
    });
    UpdateAdvisory.level.addListener(_applyUpdateAdvisory);
    UpdateAdvisory.responses.addListener(_applyUpdateAdvisory);

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
    _blockerRecheck?.cancel();
    UpdateAdvisory.level.removeListener(_applyUpdateAdvisory);
    UpdateAdvisory.responses.removeListener(_applyUpdateAdvisory);
    _installSub?.cancel();
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
          navigatorObservers: [
            if (FirebaseService.analytics != null)
              FirebaseAnalyticsObserver(analytics: FirebaseService.analytics!),
            _updateRetryObserver,
          ],
          title: AppEnvironmentConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.theme,
          home: _isMaintenanceMode
              ? MaintenanceScreen(
                  message: FirebaseService.maintenanceMessage,
                  eta: FirebaseService.maintenanceEta,
                  onCheckAgain: _handleCheckAgain,
                )
              : _wrapWithUpdateBlocker(
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
                            if (_hasAuthenticatedContext) {
                              AppAnalytics.logout();
                            }
                            _hasAuthenticatedContext = false;
                            CrashContext.clear();
                            _outletScopeCubit.reset();
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          } else if (state is AccessBlockedState) {
                            if (_hasAuthenticatedContext) {
                              AppAnalytics.logout();
                            }
                            _hasAuthenticatedContext = false;
                            CrashContext.clear();
                          } else if (state is AuthenticatedState) {
                            if (!_hasAuthenticatedContext) {
                              AppAnalytics.login();
                            }
                            _hasAuthenticatedContext = true;
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
                            } else {
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
                            CrashContext.setAuthenticated(
                              userId: state.user.id,
                              storeId: state.currentStore.storeId,
                              outletId: _outletScopeCubit.state.activeOutletId,
                              role: state.currentStore.role,
                              environment: AppEnvironmentConfig.name,
                            );
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

                        if (state is DeletionPendingState) {
                          return AccountRestoreScreen(
                            scheduledFor: state.scheduledFor,
                            isOwner: state.isOwner,
                            authRepository: widget.authRepository,
                            onRestored: () {
                              _authBloc.add(CheckAuthStatusEvent());
                            },
                            onSignOut: () {
                              _authBloc.add(LogoutRequestedEvent());
                            },
                          );
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
