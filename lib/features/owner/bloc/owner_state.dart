import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/models/store_profile_model.dart';

enum OwnerSection { dashboard, expenses, staff, paymentMethods, profile }

class OwnerState {
  final bool isLoading;
  final Set<OwnerSection> loading;
  final String? error;
  final String? actionMessage;
  final OwnerSection? messageSection;
  final DashboardMetrics metrics;
  final List<Expense> expenses;
  final List<StaffMember> staff;
  final List<StorePaymentMethod> paymentMethods;
  final StoreProfile? storeProfile;
  final String dashboardPeriod; // 'today' | '7d' | '30d'

  OwnerState({
    bool? isLoading,
    this.loading = const {},
    this.error,
    this.actionMessage,
    this.messageSection,
    DashboardMetrics? metrics,
    this.expenses = const [],
    this.staff = const [],
    this.paymentMethods = const [],
    this.storeProfile,
    this.dashboardPeriod = 'today',
  }) : isLoading = isLoading ?? loading.isNotEmpty,
       metrics = metrics ?? DashboardMetrics();

  OwnerState copyWith({
    bool? isLoading,
    Set<OwnerSection>? loading,
    String? error,
    String? actionMessage,
    OwnerSection? messageSection,
    DashboardMetrics? metrics,
    List<Expense>? expenses,
    List<StaffMember>? staff,
    List<StorePaymentMethod>? paymentMethods,
    StoreProfile? storeProfile,
    String? dashboardPeriod,
  }) {
    final nextLoading = loading ?? this.loading;
    return OwnerState(
      isLoading:
          isLoading ??
          (loading != null ? nextLoading.isNotEmpty : this.isLoading),
      loading: nextLoading,
      error: error,
      actionMessage: actionMessage,
      messageSection: messageSection,
      metrics: metrics ?? this.metrics,
      expenses: expenses ?? this.expenses,
      staff: staff ?? this.staff,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      storeProfile: storeProfile ?? this.storeProfile,
      dashboardPeriod: dashboardPeriod ?? this.dashboardPeriod,
    );
  }
}
