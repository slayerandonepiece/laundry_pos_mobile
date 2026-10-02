import 'dart:async';

import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/shared/widgets/period_filter.dart';

abstract class OwnerEvent {}

// Load* events read the local cache only (network only when nothing is
// cached yet); refresh: true is for pull-to-refresh, Refresh and Sync now.

class LoadDashboardEvent extends OwnerEvent {
  final String? from;
  final String? to;
  final String? granularity;
  final bool refresh;
  final Completer<void>? done;

  /// True for the period the dashboard opens with — the only one whose
  /// response is cached and may be shown from cache. Every other period is
  /// always fetched. Defaults to "no explicit range given"; the screen sets it
  /// explicitly for its month-to-date default, which does carry a range.
  final bool isDefaultPeriod;

  /// Identifies the selection (period + outlet scope) this request is for;
  /// echoed into [OwnerState.dashboardKey] so the screen can tell when the
  /// metrics it holds belong to a different selection.
  final String? requestKey;

  LoadDashboardEvent({
    this.from,
    this.to,
    this.granularity,
    this.refresh = false,
    this.done,
    bool? isDefaultPeriod,
    this.requestKey,
  }) : isDefaultPeriod = isDefaultPeriod ?? (from == null && to == null);
}

class LoadOutletRollupsEvent extends OwnerEvent {
  final bool allOutlets;
  final String from;
  final String to;

  LoadOutletRollupsEvent({
    required this.allOutlets,
    required this.from,
    required this.to,
  });
}

/// One card asks for its own period. The page's default period needs no
/// request — send [ResetCardEvent] instead.
class LoadCardMetricsEvent extends OwnerEvent {
  final DashboardCard card;
  final PeriodRange range;

  /// Identifies range + outlet scope; a reply for any other key is dropped.
  final String requestKey;

  LoadCardMetricsEvent({
    required this.card,
    required this.range,
    required this.requestKey,
  });
}

/// Loads the same-length window just before [range] so the sales chart can
/// draw a faint comparison line. Failures are silent: the main chart is
/// unaffected.
class LoadPreviousPeriodEvent extends OwnerEvent {
  final PeriodRange range;

  /// Identifies range + outlet scope; a reply for any other key is dropped.
  final String requestKey;

  LoadPreviousPeriodEvent({required this.range, required this.requestKey});
}

/// Back to the page's own data for these cards (default period, outlet switch).
class ResetCardEvent extends OwnerEvent {
  final Set<DashboardCard> cards;

  ResetCardEvent(this.cards);
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
  final String? idempotencyKey;
  final String? outletId;
  final bool orgWide;

  AddExpenseEvent({
    required this.title,
    required this.category,
    required this.amount,
    required this.due,
    this.monthly = false,
    this.idempotencyKey,
    this.outletId,
    this.orgWide = false,
  });
}

class UpdateExpenseEvent extends OwnerEvent {
  final String expenseId;
  final String title;
  final String category;
  final int amount;
  final String due;
  final String? outletId;

  UpdateExpenseEvent({
    required this.expenseId,
    required this.title,
    required this.category,
    required this.amount,
    required this.due,
    this.outletId,
  });
}

class DeleteExpenseEvent extends OwnerEvent {
  final String expenseId;

  DeleteExpenseEvent(this.expenseId);
}

class MarkExpensePaidEvent extends OwnerEvent {
  final String expenseId;
  final String? paidDate;

  MarkExpensePaidEvent(this.expenseId, {this.paidDate});
}

class LoadStaffEvent extends OwnerEvent {
  final bool refresh;
  final Completer<void>? done;

  LoadStaffEvent({this.refresh = false, this.done});
}

class AddStaffEvent extends OwnerEvent {
  final String name;
  final String phone;
  final String password;
  final String? idempotencyKey;
  final List<String>? outletIds;
  final String? defaultOutletId;

  AddStaffEvent({
    required this.name,
    required this.phone,
    required this.password,
    this.idempotencyKey,
    this.outletIds,
    this.defaultOutletId,
  });
}

class ToggleStaffActiveEvent extends OwnerEvent {
  final String employeeId;

  ToggleStaffActiveEvent(this.employeeId);
}

class UpdateStaffEvent extends OwnerEvent {
  final String employeeId;
  final String name;
  final String phone;
  final String? password;

  /// Only set when the owner changed the employee's outlets.
  final List<String>? outletIds;
  final String? defaultOutletId;

  UpdateStaffEvent({
    required this.employeeId,
    required this.name,
    required this.phone,
    this.password,
    this.outletIds,
    this.defaultOutletId,
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
