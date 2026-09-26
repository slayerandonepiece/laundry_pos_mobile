import 'dart:async';

abstract class OwnerEvent {}

// Load* events read the local cache only (network only when nothing is
// cached yet); refresh: true is for pull-to-refresh, Refresh and Sync now.

class LoadDashboardEvent extends OwnerEvent {
  final String? from;
  final String? to;
  final bool refresh;
  final Completer<void>? done;

  LoadDashboardEvent({this.from, this.to, this.refresh = false, this.done});
}

class LoadExpensesEvent extends OwnerEvent {
  final bool refresh;
  final Completer<void>? done;

  LoadExpensesEvent({this.refresh = false, this.done});
}

class AddExpenseEvent extends OwnerEvent {
  final String title;
  final String category;
  final int amount;
  final String due;
  final bool monthly;

  AddExpenseEvent({
    required this.title,
    required this.category,
    required this.amount,
    required this.due,
    this.monthly = false,
  });
}

class MarkExpensePaidEvent extends OwnerEvent {
  final String expenseId;

  MarkExpensePaidEvent(this.expenseId);
}

class LoadStaffEvent extends OwnerEvent {
  final bool refresh;
  final Completer<void>? done;

  LoadStaffEvent({this.refresh = false, this.done});
}

class AddStaffEvent extends OwnerEvent {
  final String name;
  final String username;
  final String password;

  AddStaffEvent({
    required this.name,
    required this.username,
    required this.password,
  });
}

class ToggleStaffActiveEvent extends OwnerEvent {
  final String employeeId;

  ToggleStaffActiveEvent(this.employeeId);
}

class UpdateStaffEvent extends OwnerEvent {
  final String employeeId;
  final String name;
  final String username;

  UpdateStaffEvent({
    required this.employeeId,
    required this.name,
    required this.username,
  });
}

class LoadPaymentMethodsEvent extends OwnerEvent {
  final bool refresh;
  final Completer<void>? done;

  LoadPaymentMethodsEvent({this.refresh = false, this.done});
}

class TogglePaymentMethodEvent extends OwnerEvent {
  final String id;
  final bool active;

  TogglePaymentMethodEvent({required this.id, required this.active});
}

class LoadStoreProfileEvent extends OwnerEvent {
  final bool refresh;
  final Completer<void>? done;

  LoadStoreProfileEvent({this.refresh = false, this.done});
}

class UpdateStoreProfileEvent extends OwnerEvent {
  final String storeName;
  final String address;
  final String phone;
  final String name;
  final String email;

  UpdateStoreProfileEvent({
    required this.storeName,
    required this.address,
    required this.phone,
    required this.name,
    required this.email,
  });
}

class ChangePasswordSubmittedEvent extends OwnerEvent {
  final String currentPassword;
  final String newPassword;

  ChangePasswordSubmittedEvent({
    required this.currentPassword,
    required this.newPassword,
  });
}
