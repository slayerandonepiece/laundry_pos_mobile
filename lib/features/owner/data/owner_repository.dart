import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/models/store_profile_model.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';

class OwnerRepository {
  final ApiClient apiClient;

  OwnerRepository({ApiClient? apiClient})
    : apiClient = apiClient ?? ApiClient();

  /// Fetches aggregated metrics for dashboard & reports
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
  }) async {
    final query = <String, String>{};
    if (from != null && from.isNotEmpty) query['from'] = from;
    if (to != null && to.isNotEmpty) query['to'] = to;

    final uri = Uri.parse(ApiEndpoints.dashboard)
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await apiClient.get(uri.toString());

    if (response is Map) {
      return DashboardMetrics.fromJson(Map<String, dynamic>.from(response));
    }
    return DashboardMetrics();
  }

  /// Lists all expenses for current store
  Future<List<Expense>> listExpenses() async {
    final response = await apiClient.get(ApiEndpoints.expenses);
    if (response is List) {
      return response
          .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return [];
  }

  /// Creates a new expense
  Future<Expense> createExpense({
    required String title,
    required String category,
    required int amount,
    required String due,
    bool monthly = false,
  }) async {
    final response = await apiClient.post(
      ApiEndpoints.expenses,
      body: {
        'title': title.trim(),
        'category': category.trim(),
        'amount': amount,
        'due': due,
        'monthly': monthly,
      },
    );
    return Expense.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Marks an expense paid
  Future<void> markExpensePaid(String expenseId) async {
    await apiClient.post(ApiEndpoints.markExpensePaid(expenseId), body: {});
  }

  /// Lists staff / employees for active store
  Future<List<StaffMember>> listStaff() async {
    final response = await apiClient.get(ApiEndpoints.employees);
    if (response is List) {
      return response
          .map((s) => StaffMember.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
    }
    return [];
  }

  /// Adds a new staff member with a generated or chosen temporary password
  Future<StaffMember> createStaff({
    required String name,
    required String username,
    required String password,
  }) async {
    final response = await apiClient.post(
      ApiEndpoints.employees,
      body: {
        'name': name.trim(),
        'username': username.trim(),
        'password': password,
      },
    );
    return StaffMember.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Toggles active status of employee
  Future<void> toggleStaffActive(String employeeId) async {
    await apiClient.patch(
      ApiEndpoints.toggleEmployeeActive(employeeId),
      body: {},
    );
  }

  /// Updates staff member details
  Future<StaffMember> updateStaff({
    required String employeeId,
    required String name,
    required String username,
  }) async {
    final response = await apiClient.patch(
      ApiEndpoints.employeeDetail(employeeId),
      body: {
        'name': name.trim(),
        'username': username.trim(),
      },
    );
    return StaffMember.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Lists store payment methods
  Future<List<StorePaymentMethod>> listPaymentMethods() async {
    final response = await apiClient.get(ApiEndpoints.paymentMethods);
    if (response is List) {
      return response
          .map(
            (m) => StorePaymentMethod.fromJson(
              Map<String, dynamic>.from(m as Map),
            ),
          )
          .toList();
    }
    return [];
  }

  /// Toggles active state of payment method
  Future<void> togglePaymentMethod(String id, bool active) async {
    await apiClient.patch(
      ApiEndpoints.paymentMethodDetail(id),
      body: {'active': active},
    );
  }

  /// Creates a new payment method
  Future<StorePaymentMethod> createPaymentMethod({required String name}) async {
    final response = await apiClient.post(
      ApiEndpoints.paymentMethods,
      body: {'name': name.trim()},
    );
    return StorePaymentMethod.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Renames an existing payment method
  Future<StorePaymentMethod> renamePaymentMethod({
    required String id,
    required String name,
  }) async {
    final response = await apiClient.patch(
      ApiEndpoints.paymentMethodDetail(id),
      body: {'name': name.trim()},
    );
    return StorePaymentMethod.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Fetches store profile (customer-facing info)
  Future<StoreProfile> getStoreProfile() async {
    final response = await apiClient.get(ApiEndpoints.profile);
    if (response is Map) {
      return StoreProfile.fromJson(Map<String, dynamic>.from(response));
    }
    throw Exception('Failed to load store profile');
  }

  /// Updates store profile
  Future<StoreProfile> updateStoreProfile({
    required String storeName,
    required String address,
    required String phone,
    required String name,
    required String email,
  }) async {
    final response = await apiClient.patch(
      ApiEndpoints.profile,
      body: {
        'storeName': storeName.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'name': name.trim(),
        'email': email.trim(),
      },
    );
    return StoreProfile.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Owner changes personal password
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await apiClient.post(
      ApiEndpoints.changePassword,
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  /// Creates a new catalogue service/product
  Future<Product> createProduct({
    required String name,
    required String category,
    required String unit,
    required int price,
    List<Map<String, dynamic>> slabs = const [],
    bool? active,
    int? extra,
  }) async {
    final response = await apiClient.post(
      ApiEndpoints.products,
      body: {
        'name': name.trim(),
        'category': category.trim(),
        'unit': unit,
        'price': price,
        if (slabs.isNotEmpty) 'slabs': slabs,
        'active': ?active,
        'extra': ?extra,
      },
    );
    return Product.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Updates an existing product
  Future<Product> updateProduct({
    required String id,
    required String name,
    required String category,
    required String unit,
    required int price,
    List<Map<String, dynamic>> slabs = const [],
    bool? active,
    int? extra,
  }) async {
    final response = await apiClient.patch(
      '${ApiEndpoints.products}/$id',
      body: {
        'name': name.trim(),
        'category': category.trim(),
        'unit': unit,
        'price': price,
        'slabs': slabs,
        'active': ?active,
        'extra': ?extra,
      },
    );
    return Product.fromJson(Map<String, dynamic>.from(response as Map));
  }
}
