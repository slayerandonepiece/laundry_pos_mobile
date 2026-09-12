import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
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
import 'package:myshop/features/shell/presentation/main_navigation_shell.dart';
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
  late final AuthBloc _authBloc;
  late final CartBloc _cartBloc;
  late final OrdersBloc _ordersBloc;
  late final OwnerBloc _ownerBloc;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.start();

    _authBloc = AuthBloc(
      authRepository: widget.authRepository,
      localCache: widget.localCache,
    )..add(CheckAuthStatusEvent());

    _cartBloc = CartBloc(posRepository: widget.posRepository);

    _ordersBloc = OrdersBloc(ordersRepository: widget.ordersRepository);

    _ownerBloc = OwnerBloc(ownerRepository: widget.ownerRepository);

    // Automatic 401 handling: session revocation triggers immediate sign-out
    widget.apiClient.onUnauthorized = () {
      if (_authBloc.state is AuthenticatedState) {
        _authBloc.add(SessionRevokedEvent());
      }
    };

    // Automatic 403 handling: access denial triggers blocked screen live
    widget.apiClient.onForbidden = (reason, paidThroughDate) {
      if (_authBloc.state is AuthenticatedState) {
        _authBloc.add(
          AccessForbiddenEvent(
            reason: reason,
            paidThroughDate: paidThroughDate,
          ),
        );
      }
    };
  }

  @override
  void dispose() {
    ConnectivityService.instance.dispose();
    _authBloc.close();
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
          BlocProvider<CartBloc>.value(value: _cartBloc),
          BlocProvider<OrdersBloc>.value(value: _ordersBloc),
          BlocProvider<OwnerBloc>.value(value: _ownerBloc),
        ],
        child: MaterialApp(
          title: 'MyShop',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.theme,
          home: BlocConsumer<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state is UnauthenticatedState) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              } else if (state is AuthenticatedState) {
                // Preload catalog and orders upon authenticating.
                // For fresh login, initial loading is handled by BootstrapScreen.
                if (!state.isFreshLogin) {
                  _cartBloc.add(LoadCatalogEvent());
                  _ordersBloc.add(LoadOrdersEvent());
                  if (state.isOwner) {
                    _ownerBloc.add(LoadDashboardEvent());
                    _ownerBloc.add(LoadExpensesEvent());
                  }
                }
              }
            },
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
                  onSignOut: () {
                    _authBloc.add(LogoutRequestedEvent());
                  },
                );
              }

              if (state is AuthenticatedState) {
                if (state.isFreshLogin) {
                  return BootstrapScreen(
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
              }

              // Default: UnauthenticatedState or AuthLoadingState (when signing in)
              return const LoginScreen();
            },
          ),
        ),
      ),
    );
  }
}
