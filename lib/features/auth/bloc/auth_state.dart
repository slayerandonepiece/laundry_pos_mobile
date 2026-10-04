import '../data/models/user_model.dart';

abstract class AuthState {}

class AuthInitialState extends AuthState {}

class AuthLoadingState extends AuthState {
  final String? message;
  final bool isInitialCheck;

  AuthLoadingState({this.message, this.isInitialCheck = false});
}

class UnauthenticatedState extends AuthState {
  final String? errorMessage;
  final bool noActiveStore;

  UnauthenticatedState({this.errorMessage, this.noActiveStore = false});
}

class MustChangePasswordState extends AuthState {
  final User user;
  final String? errorMessage;

  MustChangePasswordState({required this.user, this.errorMessage});
}

/// Signed in, but the account is scheduled for deletion. Nothing else is
/// usable until the user restores it or signs out.
class DeletionPendingState extends AuthState {
  final User user;
  final String scheduledFor;
  final bool isOwner;

  DeletionPendingState({
    required this.user,
    required this.scheduledFor,
    required this.isOwner,
  });
}

class AccessBlockedState extends AuthState {
  final String reason;
  final String? paidThroughDate;
  final bool isOwner;
  final String? ownerPhone;

  AccessBlockedState({
    required this.reason,
    this.paidThroughDate,
    required this.isOwner,
    this.ownerPhone,
  });
}

class AuthenticatedState extends AuthState {
  final User user;
  final StoreSummary currentStore;
  final List<StoreSummary> availableStores;
  final bool isFreshLogin;

  AuthenticatedState({
    required this.user,
    required this.currentStore,
    required this.availableStores,
    this.isFreshLogin = false,
  });

  bool get isOwner => currentStore.isOwner;
  bool get isEmployee => currentStore.isEmployee;
  bool get hasMultipleStores => availableStores.length > 1;

  AuthenticatedState copyWith({
    User? user,
    StoreSummary? currentStore,
    List<StoreSummary>? availableStores,
    bool? isFreshLogin,
  }) {
    return AuthenticatedState(
      user: user ?? this.user,
      currentStore: currentStore ?? this.currentStore,
      availableStores: availableStores ?? this.availableStores,
      isFreshLogin: isFreshLogin ?? this.isFreshLogin,
    );
  }
}
