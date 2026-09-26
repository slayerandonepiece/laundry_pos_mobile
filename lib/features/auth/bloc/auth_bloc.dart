import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';

import 'auth_event.dart';
import 'auth_state.dart';

const _tag = 'AUTH_BLOC';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;
  final LocalCacheService _localCache;

  AuthBloc({required this.authRepository, LocalCacheService? localCache})
    : _localCache = localCache ?? LocalCacheService(),
      super(AuthInitialState()) {
    on<CheckAuthStatusEvent>(_onCheckAuthStatus);
    on<LoginSubmittedEvent>(_onLoginSubmitted);
    on<StoreSelectedEvent>(_onStoreSelected);
    on<SetPasswordSubmittedEvent>(_onSetPasswordSubmitted);
    on<SessionRevokedEvent>(_onSessionRevoked);
    on<AccessForbiddenEvent>(_onAccessForbidden);
    on<LogoutRequestedEvent>(_onLogoutRequested);
    on<BootstrapCompletedEvent>(_onBootstrapCompleted);
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatusEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoadingState(isInitialCheck: true));
    try {
      final result = await authRepository.checkSession();
      if (result == null) {
        emit(UnauthenticatedState());
        return;
      }
      _resolveAuthResult(result, emit, isFreshLogin: false);
    } catch (e) {
      if (e is AuthException && e.code == 'FORBIDDEN') {
        final cached = _localCache.getCachedStoreDetails();
        final isOwner =
            cached != null &&
            cached['role']?.toString().toUpperCase() == 'OWNER';
        emit(
          AccessBlockedState(
            reason: e.reason ?? 'store_locked',
            paidThroughDate: e.paidThroughDate,
            isOwner: isOwner,
          ),
        );
      } else {
        emit(UnauthenticatedState());
      }
    }
  }

  Future<void> _onLoginSubmitted(
    LoginSubmittedEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoadingState(message: 'Signing in...'));
    try {
      final result = await authRepository.login(event.username, event.password);
      _resolveAuthResult(result, emit, isFreshLogin: true);
    } on AuthException catch (e) {
      if (e.code == 'FORBIDDEN') {
        final cached = _localCache.getCachedStoreDetails();
        final isOwner =
            cached != null &&
            cached['role']?.toString().toUpperCase() == 'OWNER';
        emit(
          AccessBlockedState(
            reason: e.reason ?? 'store_locked',
            paidThroughDate: e.paidThroughDate,
            isOwner: isOwner,
          ),
        );
      } else {
        emit(UnauthenticatedState(errorMessage: e.message));
      }
    } on ApiException catch (e) {
      emit(UnauthenticatedState(errorMessage: e.message));
    } catch (_) {
      emit(
        UnauthenticatedState(
          errorMessage: 'Unable to connect to server. Please try again.',
        ),
      );
    }
  }

  void _resolveAuthResult(
    AuthResult result,
    Emitter<AuthState> emit, {
    bool isFreshLogin = false,
  }) {
    if (result.stores.isEmpty) {
      emit(UnauthenticatedState(noActiveStore: true));
      return;
    }

    if (result.user.mustChangePassword) {
      emit(MustChangePasswordState(user: result.user));
      return;
    }

    final activeStoreId = _localCache.getActiveStoreId();
    final activeStore = result.stores.firstWhere(
      (s) => s.storeId == activeStoreId,
      orElse: () => result.stores.first,
    );

    // Save active store and available stores to local cache
    _localCache.setActiveStoreId(activeStore.storeId);
    _localCache.setCachedStoreDetails(activeStore.toJson());
    _localCache.setCachedAvailableStores(
      result.stores.map((s) => s.toJson()).toList(),
    );
    _localCache.setCachedUser(result.user.toJson());

    if (activeStore.isBlocked) {
      emit(
        AccessBlockedState(
          reason: activeStore.blockedReason!,
          paidThroughDate: activeStore.paidThroughDate,
          isOwner: activeStore.isOwner,
        ),
      );
      return;
    }

    emit(
      AuthenticatedState(
        user: result.user,
        currentStore: activeStore,
        availableStores: result.stores,
        isFreshLogin: isFreshLogin,
      ),
    );
  }

  Future<void> _onStoreSelected(
    StoreSelectedEvent event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    if (current is AuthenticatedState) {
      await authRepository.selectStore(event.storeId);
      final newStore = current.availableStores.firstWhere(
        (s) => s.storeId == event.storeId,
        orElse: () => current.currentStore,
      );

      _localCache.setActiveStoreId(newStore.storeId);
      _localCache.setCachedStoreDetails(newStore.toJson());

      if (newStore.isBlocked) {
        emit(
          AccessBlockedState(
            reason: newStore.blockedReason!,
            paidThroughDate: newStore.paidThroughDate,
            isOwner: newStore.isOwner,
          ),
        );
        return;
      }

      emit(
        AuthenticatedState(
          user: current.user,
          currentStore: newStore,
          availableStores: current.availableStores,
          isFreshLogin: false,
        ),
      );
    }
  }

  Future<void> _onSetPasswordSubmitted(
    SetPasswordSubmittedEvent event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    if (current is! MustChangePasswordState) return;

    if (event.newPassword.length < 8) {
      emit(
        MustChangePasswordState(
          user: current.user,
          errorMessage: 'Password must be at least 8 characters long.',
        ),
      );
      return;
    }

    if (event.newPassword != event.confirmPassword) {
      emit(
        MustChangePasswordState(
          user: current.user,
          errorMessage: "Passwords don't match. Please re-enter.",
        ),
      );
      return;
    }

    emit(AuthLoadingState(message: 'Updating password...'));
    try {
      await authRepository.setPassword(event.newPassword);
      add(CheckAuthStatusEvent());
    } catch (e) {
      AppLogger.log(_tag, 'set password failed', error: e);
      emit(
        MustChangePasswordState(
          user: current.user,
          errorMessage: 'Could not set password — try again',
        ),
      );
    }
  }

  Future<void> _onSessionRevoked(
    SessionRevokedEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is! AuthenticatedState) return;
    await authRepository.logout();
    emit(
      UnauthenticatedState(
        errorMessage: 'Your session has expired. Please sign in again.',
      ),
    );
  }

  Future<void> _onAccessForbidden(
    AccessForbiddenEvent event,
    Emitter<AuthState> emit,
  ) async {
    final reason = event.reason;
    if (reason == null || reason.isEmpty) {
      // No organization-level blockedReason attached — this is an
      // outlet-scoped 403 (e.g. the active outlet's access changed) or one
      // of the other reason-less FORBIDDEN cases (role/membership changed
      // server-side). None of those are "store locked": defaulting here
      // used to mislabel every one of them with that screen. Force a fresh
      // sign-in instead (O0.3), which also re-resolves outlet scope on the
      // next login.
      await _localCache.clearActiveOutletId();
      await authRepository.logout();
      emit(
        UnauthenticatedState(
          errorMessage: 'Your access changed. Please sign in again.',
        ),
      );
      return;
    }
    final current = state;
    final isOwner = current is AuthenticatedState ? current.isOwner : false;
    emit(
      AccessBlockedState(
        reason: reason,
        paidThroughDate: event.paidThroughDate,
        isOwner: isOwner,
      ),
    );
  }

  Future<void> _onLogoutRequested(
    LogoutRequestedEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await authRepository.logout();
    } catch (_) {
      // Ignored: If initiated from ProfileScreen, logout has already succeeded.
    }
    emit(UnauthenticatedState());
  }

  void _onBootstrapCompleted(
    BootstrapCompletedEvent event,
    Emitter<AuthState> emit,
  ) {
    if (state is AuthenticatedState) {
      emit((state as AuthenticatedState).copyWith(isFreshLogin: false));
    }
  }
}
