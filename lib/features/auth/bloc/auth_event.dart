abstract class AuthEvent {}

class CheckAuthStatusEvent extends AuthEvent {}

class LoginSubmittedEvent extends AuthEvent {
  final String phone;
  final String password;

  LoginSubmittedEvent({required this.phone, required this.password});
}

class StoreSelectedEvent extends AuthEvent {
  final String storeId;

  StoreSelectedEvent(this.storeId);
}

class SetPasswordSubmittedEvent extends AuthEvent {
  final String newPassword;
  final String confirmPassword;

  SetPasswordSubmittedEvent({
    required this.newPassword,
    required this.confirmPassword,
  });
}

class SessionRevokedEvent extends AuthEvent {}

class AccessForbiddenEvent extends AuthEvent {
  final String? reason;
  final String? paidThroughDate;

  AccessForbiddenEvent({this.reason, this.paidThroughDate});
}

class LogoutRequestedEvent extends AuthEvent {}

class BootstrapCompletedEvent extends AuthEvent {}
