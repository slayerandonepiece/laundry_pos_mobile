import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/models/store_profile_model.dart';

class OwnerState {
  final bool isLoading;
  final String? error;
  final String? actionMessage;
  final DashboardMetrics metrics;
  final List<Expense> expenses;
  final List<StaffMember> staff;
  final List<StorePaymentMethod> paymentMethods;
  final StoreProfile? storeProfile;
  final String dashboardPeriod; // 'today' | '7d' | '30d'

  OwnerState({
    this.isLoading = false,
    this.error,
    this.actionMessage,
    DashboardMetrics? metrics,
    this.expenses = const [],
    this.staff = const [],
    this.paymentMethods = const [],
    this.storeProfile,
    this.dashboardPeriod = 'today',
  }) : metrics = metrics ?? DashboardMetrics();

  OwnerState copyWith({
    bool? isLoading,
    String? error,
    String? actionMessage,
    DashboardMetrics? metrics,
    List<Expense>? expenses,
    List<StaffMember>? staff,
    List<StorePaymentMethod>? paymentMethods,
    StoreProfile? storeProfile,
    String? dashboardPeriod,
  }) {
    return OwnerState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      actionMessage: actionMessage,
      metrics: metrics ?? this.metrics,
      expenses: expenses ?? this.expenses,
      staff: staff ?? this.staff,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      storeProfile: storeProfile ?? this.storeProfile,
      dashboardPeriod: dashboardPeriod ?? this.dashboardPeriod,
    );
  }
}
