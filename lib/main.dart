import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/app_resume_sync.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/theme/app_theme.dart';
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
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/bloc/cart_event.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/features/shell/presentation/main_navigation_shell.dart';
import 'package:myshop/features/shell/presentation/outlet_required_screen.dart';
import 'package:myshop/shared/widgets/blocked_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class _MyShopAppState extends State<MyShopApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _rescoping = false;

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
      state.isFreshLogin || widget.localCache.getCachedOrders() == null;

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
      final fresh = await widget.authRepository.refreshOutletContext();
      if (fresh == null ||
          fresh.any((o) => o['id']?.toString() == previous)) {
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

  @override
  void initState() {
    super.initState();
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
          title: 'MyShop',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.theme,
          home: MultiBlocListener(
            listeners: [
              BlocListener<AuthBloc, AuthState>(
                listener: (context, state) {
                  if (state is UnauthenticatedState) {
                    _outletScopeCubit.reset();
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  } else if (state is AuthenticatedState) {
                    if (state.isFreshLogin) {
                      // Resolve the O3 initial outlet scope before
                      // BootstrapScreen (which fetches orders directly) ever
                      // mounts — otherwise an employee who hasn't picked an
                      // outlet yet 403s immediately.
                      _outletScopeCubit.adoptFromLogin(isOwner: state.isOwner);
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
              if (state is AuthInitialState ||
                  (state is AuthLoadingState && state.isInitialCheck)) {
                return const SplashScreen();
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
                  pendingCount: widget.localCache.getTotalPendingCount(),
                );
              }

              if (state is AuthenticatedState) {
                return BlocBuilder<OutletScopeCubit, OutletScope>(
                  builder: (context, scope) {
                    if (scope.missingCache) {
                      // SessionRevokedEvent was just dispatched from the
                      // listener above; show a brief transitional splash
                      // rather than guessing an outlet.
                      return const SplashScreen();
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
                        pendingCount: widget.localCache.getTotalPendingCount(),
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
                          scope.allOutlets ? 'all' : scope.activeOutletId,
                        ),
                        authState: state,
                        authRepository: widget.authRepository,
                        posRepository: widget.posRepository,
                        ordersRepository: widget.ordersRepository,
                        ownerRepository: widget.ownerRepository,
                        localCache: widget.localCache,
                        onCompleted: () {
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
    );
  }
}
