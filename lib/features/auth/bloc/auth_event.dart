abstract class AuthEvent {}

class CheckAuthStatusEvent extends AuthEvent {}

/// Silent re-check of the session while the app is in use (for example on
/// resume). Unlike [CheckAuthStatusEvent] it shows no loading screen and never
/// signs the user out on a transient failure.
class RefreshAuthStatusEvent extends AuthEvent {}

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
