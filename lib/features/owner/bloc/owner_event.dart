abstract class OwnerEvent {}

class LoadDashboardEvent extends OwnerEvent {
  final String? from;
  final String? to;

  LoadDashboardEvent({this.from, this.to});
}

class LoadExpensesEvent extends OwnerEvent {}

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

class LoadStaffEvent extends OwnerEvent {}

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

class LoadPaymentMethodsEvent extends OwnerEvent {}

class TogglePaymentMethodEvent extends OwnerEvent {
  final String id;
  final bool active;

  TogglePaymentMethodEvent({required this.id, required this.active});
}

class LoadStoreProfileEvent extends OwnerEvent {}

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
