import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/models/store_profile_model.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';

const _tag = 'OWNER_REPO';

class OwnerRepository {
  final ApiClient apiClient;
  final LocalCacheService localCache;

  OwnerRepository({ApiClient? apiClient, LocalCacheService? localCache})
    : apiClient = apiClient ?? ApiClient(),
      localCache = localCache ?? LocalCacheService();

  /// Reads dashboard metrics from the local cache only — no network call.
  DashboardMetrics? getCachedDashboardMetricsSync() {
    try {
      final cached = localCache.getCachedDashboardMetrics();
      if (cached == null || cached.isEmpty) return null;
      return DashboardMetrics.fromJson(cached);
    } catch (_) {
      return null;
    }
  }

  /// Fetches aggregated metrics for dashboard & reports
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
  }) async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      final cached = localCache.getCachedDashboardMetrics();
      if (cached != null && cached.isNotEmpty) {
        final metrics = DashboardMetrics.fromJson(cached);
        final pendingCount = localCache.getTotalPendingCount();
        SyncManager.instance.setOffline(
          pendingCount,
          'Offline · using cached dashboard',
        );
        return metrics;
      }
      throw Exception(
        'No network connection and no cached dashboard metrics available',
      );
    }

    final query = <String, String>{};
    if (from != null && from.isNotEmpty) query['from'] = from;
    if (to != null && to.isNotEmpty) query['to'] = to;
    final outletId = localCache.getActiveOutletId();
    if (outletId != null && !localCache.isAllOutletsScope()) {
      query['outletId'] = outletId;
    }

    final uri = Uri.parse(ApiEndpoints.dashboard)
        .replace(queryParameters: query.isEmpty ? null : query);

    SyncManager.instance.startSync('Fetching latest from cloud...');
    try {
      final response = await apiClient.get(uri.toString());
      if (response is Map) {
        final metrics = DashboardMetrics.fromJson(
          Map<String, dynamic>.from(response),
        );
        // Only the default period is cached — it's what the dashboard opens
        // with; a custom range is always fetched.
        if (query['from'] == null && query['to'] == null) {
          await localCache.setCachedDashboardMetrics(metrics.toJson());
        }
        SyncManager.instance.completeSync();
        return metrics;
      }
      SyncManager.instance.completeSync();
      return DashboardMetrics();
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      final cached = localCache.getCachedDashboardMetrics();
      if (cached != null && cached.isNotEmpty) {
        final metrics = DashboardMetrics.fromJson(cached);
        final pendingCount = localCache.getTotalPendingCount();
        if (reallyOffline) {
          SyncManager.instance.setOffline(
            pendingCount,
            'Offline · using cached dashboard',
          );
        } else {
          AppLogger.log(_tag, 'refresh dashboard failed', error: e);
          SyncManager.instance.setError(
            'Could not refresh dashboard — showing cached data',
          );
        }
        return metrics;
      }
      rethrow;
    }
  }

  /// Reads expenses from the local cache only — no network call.
  List<Expense>? getCachedExpensesSync() {
    try {
      final cached = localCache.getCachedExpenses();
      if (cached == null || cached.isEmpty) return null;
      return cached.map((e) => Expense.fromJson(e)).toList();
    } catch (_) {
      return null;
    }
  }

  /// Lists all expenses for current store
  Future<List<Expense>> listExpenses() async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      final cached = localCache.getCachedExpenses();
      if (cached != null && cached.isNotEmpty) {
        final expenses = cached.map((e) => Expense.fromJson(e)).toList();
        final pendingCount = localCache.getTotalPendingCount();
        SyncManager.instance.setOffline(
          pendingCount,
          'Offline · using cached expenses',
        );
        return expenses;
      }
      throw Exception('No network connection and no cached expenses available');
    }

    try {
      SyncManager.instance.startSync('Fetching latest from cloud...');
      final response = await apiClient.get(ApiEndpoints.expenses);
      if (response is List) {
        final expenses = response
            .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        await localCache.setCachedExpenses(
          expenses.map((e) => e.toJson()).toList(),
        );
        SyncManager.instance.completeSync();
        return expenses;
      }
      SyncManager.instance.completeSync();
      return [];
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      final cached = localCache.getCachedExpenses();
      if (cached != null && cached.isNotEmpty) {
        final expenses = cached.map((e) => Expense.fromJson(e)).toList();
        final pendingCount = localCache.getTotalPendingCount();
        if (reallyOffline) {
          SyncManager.instance.setOffline(
            pendingCount,
            'Offline · using cached expenses',
          );
        } else {
          AppLogger.log(_tag, 'refresh expenses failed', error: e);
          SyncManager.instance.setError(
            'Could not refresh expenses — showing cached data',
          );
        }
        return expenses;
      }
      rethrow;
    }
  }

  /// Direct online API call for creating expense
  Future<Expense> _createExpenseDirect({
    required String title,
    required String category,
    required int amount,
    required String due,
    bool monthly = false,
    String? outletHeader,
  }) async {
    final response = await apiClient.post(
      ApiEndpoints.expenses,
      headers: outletHeader != null ? {'X-Outlet-Id': outletHeader} : null,
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

  Future<Expense> _createExpenseOffline({
    required String title,
    required String category,
    required int amount,
    required String due,
    bool monthly = false,
  }) async {
    final localId = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
    final localExpense = Expense(
      id: localId,
      title: title.trim(),
      category: category.trim(),
      amount: amount,
      due: due,
      monthly: monthly,
    );
    final cached = localCache.getCachedExpenses() ?? [];
    cached.insert(0, localExpense.toJson());
    await localCache.setCachedExpenses(cached);

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'create_expense',
      'outletId': localCache.isAllOutletsScope()
          ? null
          : localCache.getActiveOutletId(),
      'payload': {
        'localId': localId,
        'title': title.trim(),
        'category': category.trim(),
        'amount': amount,
        'due': due,
        'monthly': monthly,
      },
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
    return localExpense;
  }

  /// Creates a new expense
  Future<Expense> createExpense({
    required String title,
    required String category,
    required int amount,
    required String due,
    bool monthly = false,
  }) async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      return _createExpenseOffline(
        title: title,
        category: category,
        amount: amount,
        due: due,
        monthly: monthly,
      );
    }

    try {
      final expense = await _createExpenseDirect(
        title: title,
        category: category,
        amount: amount,
        due: due,
        monthly: monthly,
      );
      final cached = localCache.getCachedExpenses() ?? [];
      cached.insert(0, expense.toJson());
      await localCache.setCachedExpenses(cached);
      return expense;
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      if (reallyOffline) {
        return _createExpenseOffline(
          title: title,
          category: category,
          amount: amount,
          due: due,
          monthly: monthly,
        );
      }
      rethrow;
    }
  }

  Future<void> _markExpensePaidDirect(String expenseId) async {
    await apiClient.post(ApiEndpoints.markExpensePaid(expenseId), body: {});
  }

  Future<void> _markExpensePaidOffline(String expenseId) async {
    final cached = localCache.getCachedExpenses() ?? [];
    final idx = cached.indexWhere((e) => e['id']?.toString() == expenseId);
    if (idx != -1) {
      cached[idx] = {...cached[idx], 'paid': DateTime.now().toIso8601String()};
      await localCache.setCachedExpenses(cached);
    }

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'mark_expense_paid',
      'payload': {'expenseId': expenseId},
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
  }

  /// Marks an expense paid
  Future<void> markExpensePaid(String expenseId) async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      await _markExpensePaidOffline(expenseId);
      return;
    }

    try {
      await _markExpensePaidDirect(expenseId);
      final cached = localCache.getCachedExpenses() ?? [];
      final idx = cached.indexWhere((e) => e['id']?.toString() == expenseId);
      if (idx != -1) {
        cached[idx] = {
          ...cached[idx],
          'paid': DateTime.now().toIso8601String(),
        };
        await localCache.setCachedExpenses(cached);
      }
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      if (reallyOffline) {
        await _markExpensePaidOffline(expenseId);
        return;
      }
      rethrow;
    }
  }

  /// Reads staff from the local cache only — no network call.
  List<StaffMember>? getCachedStaffSync() {
    try {
      final cached = localCache.getCachedStaff();
      if (cached == null || cached.isEmpty) return null;
      return cached.map((s) => StaffMember.fromJson(s)).toList();
    } catch (_) {
      return null;
    }
  }

  /// Lists staff / employees for active store
  Future<List<StaffMember>> listStaff() async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      final cached = localCache.getCachedStaff();
      if (cached != null && cached.isNotEmpty) {
        final staff = cached.map((s) => StaffMember.fromJson(s)).toList();
        final pendingCount = localCache.getTotalPendingCount();
        SyncManager.instance.setOffline(
          pendingCount,
          'Offline · using cached staff',
        );
        return staff;
      }
      throw Exception('No network connection and no cached staff available');
    }

    try {
      SyncManager.instance.startSync('Fetching latest from cloud...');
      final response = await apiClient.get(ApiEndpoints.employees);
      if (response is List) {
        final staff = response
            .map(
              (s) => StaffMember.fromJson(Map<String, dynamic>.from(s as Map)),
            )
            .toList();
        await localCache.setCachedStaff(staff.map((s) => s.toJson()).toList());
        SyncManager.instance.completeSync();
        return staff;
      }
      SyncManager.instance.completeSync();
      return [];
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      final cached = localCache.getCachedStaff();
      if (cached != null && cached.isNotEmpty) {
        final staff = cached.map((s) => StaffMember.fromJson(s)).toList();
        final pendingCount = localCache.getTotalPendingCount();
        if (reallyOffline) {
          SyncManager.instance.setOffline(
            pendingCount,
            'Offline · using cached staff',
          );
        } else {
          AppLogger.log(_tag, 'refresh staff failed', error: e);
          SyncManager.instance.setError(
            'Could not refresh staff — showing cached data',
          );
        }
        return staff;
      }
      rethrow;
    }
  }

  Future<StaffMember> _createStaffDirect({
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

  Future<StaffMember> _createStaffOffline({
    required String name,
    required String username,
    required String password,
  }) async {
    final localId = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
    final localStaff = StaffMember(
      id: localId,
      name: name.trim(),
      username: username.trim(),
      active: true,
    );
    final cached = localCache.getCachedStaff() ?? [];
    cached.insert(0, localStaff.toJson());
    await localCache.setCachedStaff(cached);

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'create_staff',
      'payload': {
        'localId': localId,
        'name': name.trim(),
        'username': username.trim(),
        'password': password,
      },
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
    return localStaff;
  }

  /// Adds a new staff member with a generated or chosen temporary password
  Future<StaffMember> createStaff({
    required String name,
    required String username,
    required String password,
  }) async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      return _createStaffOffline(
        name: name,
        username: username,
        password: password,
      );
    }

    try {
      final staff = await _createStaffDirect(
        name: name,
        username: username,
        password: password,
      );
      final cached = localCache.getCachedStaff() ?? [];
      cached.insert(0, staff.toJson());
      await localCache.setCachedStaff(cached);
      return staff;
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      if (reallyOffline) {
        return _createStaffOffline(
          name: name,
          username: username,
          password: password,
        );
      }
      rethrow;
    }
  }

  Future<void> _toggleStaffActiveDirect(String employeeId) async {
    await apiClient.patch(
      ApiEndpoints.toggleEmployeeActive(employeeId),
      body: {},
    );
  }

  Future<void> _toggleStaffActiveOffline(String employeeId) async {
    final cached = localCache.getCachedStaff() ?? [];
    final idx = cached.indexWhere((s) => s['id']?.toString() == employeeId);
    if (idx != -1) {
      final currentActive = cached[idx]['active'] != false;
      cached[idx] = {...cached[idx], 'active': !currentActive};
      await localCache.setCachedStaff(cached);
    }

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'toggle_staff_active',
      'payload': {'employeeId': employeeId},
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
  }

  /// Toggles active status of employee
  Future<void> toggleStaffActive(String employeeId) async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      await _toggleStaffActiveOffline(employeeId);
      return;
    }

    try {
      await _toggleStaffActiveDirect(employeeId);
      final cached = localCache.getCachedStaff() ?? [];
      final idx = cached.indexWhere((s) => s['id']?.toString() == employeeId);
      if (idx != -1) {
        final currentActive = cached[idx]['active'] != false;
        cached[idx] = {...cached[idx], 'active': !currentActive};
        await localCache.setCachedStaff(cached);
      }
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      if (reallyOffline) {
        await _toggleStaffActiveOffline(employeeId);
        return;
      }
      rethrow;
    }
  }

  Future<StaffMember> _updateStaffDirect({
    required String employeeId,
    required String name,
    required String username,
  }) async {
    final response = await apiClient.patch(
      ApiEndpoints.employeeDetail(employeeId),
      body: {'name': name.trim(), 'username': username.trim()},
    );
    return StaffMember.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<StaffMember> _updateStaffOffline({
    required String employeeId,
    required String name,
    required String username,
  }) async {
    final cached = localCache.getCachedStaff() ?? [];
    final idx = cached.indexWhere((s) => s['id']?.toString() == employeeId);
    StaffMember member;
    if (idx != -1) {
      cached[idx] = {
        ...cached[idx],
        'name': name.trim(),
        'username': username.trim(),
      };
      await localCache.setCachedStaff(cached);
      member = StaffMember.fromJson(cached[idx]);
    } else {
      member = StaffMember(
        id: employeeId,
        name: name.trim(),
        username: username.trim(),
        active: true,
      );
    }

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'update_staff',
      'payload': {
        'employeeId': employeeId,
        'name': name.trim(),
        'username': username.trim(),
      },
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
    return member;
  }

  /// Updates staff member details
  Future<StaffMember> updateStaff({
    required String employeeId,
    required String name,
    required String username,
  }) async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      return _updateStaffOffline(
        employeeId: employeeId,
        name: name,
        username: username,
      );
    }

    try {
      final staff = await _updateStaffDirect(
        employeeId: employeeId,
        name: name,
        username: username,
      );
      final cached = localCache.getCachedStaff() ?? [];
      final idx = cached.indexWhere((s) => s['id']?.toString() == employeeId);
      if (idx != -1) {
        cached[idx] = staff.toJson();
        await localCache.setCachedStaff(cached);
      }
      return staff;
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      if (reallyOffline) {
        return _updateStaffOffline(
          employeeId: employeeId,
          name: name,
          username: username,
        );
      }
      rethrow;
    }
  }

  /// Reads payment methods from the local cache only — no network call.
  List<StorePaymentMethod>? getCachedPaymentMethodsSync() {
    try {
      final cached = localCache.getCachedPaymentMethods();
      if (cached == null || cached.isEmpty) return null;
      return cached.map((m) => StorePaymentMethod.fromJson(m)).toList();
    } catch (_) {
      return null;
    }
  }

  /// Lists store payment methods
  Future<List<StorePaymentMethod>> listPaymentMethods() async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      final cached = localCache.getCachedPaymentMethods();
      if (cached != null && cached.isNotEmpty) {
        final methods = cached
            .map((m) => StorePaymentMethod.fromJson(m))
            .toList();
        final pendingCount = localCache.getTotalPendingCount();
        SyncManager.instance.setOffline(
          pendingCount,
          'Offline · using cached payment methods',
        );
        return methods;
      }
      throw Exception(
        'No network connection and no cached payment methods available',
      );
    }

    try {
      SyncManager.instance.startSync('Fetching latest from cloud...');
      final response = await apiClient.get(ApiEndpoints.paymentMethodsAll);
      if (response is List) {
        final methods = response
            .map(
              (m) => StorePaymentMethod.fromJson(
                Map<String, dynamic>.from(m as Map),
              ),
            )
            .toList();
        await localCache.setCachedPaymentMethods(
          methods.map((m) => m.toJson()).toList(),
        );
        SyncManager.instance.completeSync();
        return methods;
      }
      SyncManager.instance.completeSync();
      return [];
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      final cached = localCache.getCachedPaymentMethods();
      if (cached != null && cached.isNotEmpty) {
        final methods = cached
            .map((m) => StorePaymentMethod.fromJson(m))
            .toList();
        final pendingCount = localCache.getTotalPendingCount();
        if (reallyOffline) {
          SyncManager.instance.setOffline(
            pendingCount,
            'Offline · using cached payment methods',
          );
        } else {
          AppLogger.log(_tag, 'refresh payment methods failed', error: e);
          SyncManager.instance.setError(
            'Could not refresh payment methods — showing cached data',
          );
        }
        return methods;
      }
      rethrow;
    }
  }

  Future<void> _togglePaymentMethodDirect(String id, bool active) async {
    await apiClient.patch(
      ApiEndpoints.paymentMethodDetail(id),
      body: {'enabled': active},
    );
  }

  Future<void> _togglePaymentMethodOffline(String id, bool active) async {
    final cached = localCache.getCachedPaymentMethods() ?? [];
    final idx = cached.indexWhere((m) => m['id']?.toString() == id);
    if (idx != -1) {
      cached[idx] = {...cached[idx], 'active': active};
      await localCache.setCachedPaymentMethods(cached);
    }

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'toggle_payment_method',
      'payload': {'id': id, 'active': active},
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
  }

  /// Toggles active state of payment method
  Future<void> togglePaymentMethod(String id, bool active) async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      await _togglePaymentMethodOffline(id, active);
      return;
    }

    try {
      await _togglePaymentMethodDirect(id, active);
      final cached = localCache.getCachedPaymentMethods() ?? [];
      final idx = cached.indexWhere((m) => m['id']?.toString() == id);
      if (idx != -1) {
        cached[idx] = {...cached[idx], 'active': active};
        await localCache.setCachedPaymentMethods(cached);
      }
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      if (reallyOffline) {
        await _togglePaymentMethodOffline(id, active);
        return;
      }
      rethrow;
    }
  }

  /// Reads store profile from the local cache only — no network call.
  StoreProfile? getCachedStoreProfileSync() {
    try {
      final cached = localCache.getCachedStoreProfile();
      if (cached == null || cached.isEmpty) return null;
      return StoreProfile.fromJson(cached);
    } catch (_) {
      return null;
    }
  }

  /// Fetches store profile (customer-facing info)
  Future<StoreProfile> getStoreProfile() async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      final cached = localCache.getCachedStoreProfile();
      if (cached != null && cached.isNotEmpty) {
        final profile = StoreProfile.fromJson(cached);
        final pendingCount = localCache.getTotalPendingCount();
        SyncManager.instance.setOffline(
          pendingCount,
          'Offline · using cached store profile',
        );
        return profile;
      }
      throw Exception(
        'No network connection and no cached store profile available',
      );
    }

    try {
      SyncManager.instance.startSync('Fetching latest from cloud...');
      final response = await apiClient.get(ApiEndpoints.profile);
      if (response is Map) {
        final profile = StoreProfile.fromJson(
          Map<String, dynamic>.from(response),
        );
        await localCache.setCachedStoreProfile(profile.toJson());
        SyncManager.instance.completeSync();
        return profile;
      }
      throw Exception('Failed to load store profile');
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      final cached = localCache.getCachedStoreProfile();
      if (cached != null && cached.isNotEmpty) {
        final profile = StoreProfile.fromJson(cached);
        final pendingCount = localCache.getTotalPendingCount();
        if (reallyOffline) {
          SyncManager.instance.setOffline(
            pendingCount,
            'Offline · using cached store profile',
          );
        } else {
          AppLogger.log(_tag, 'refresh store profile failed', error: e);
          SyncManager.instance.setError(
            'Could not refresh store profile — showing cached data',
          );
        }
        return profile;
      }
      rethrow;
    }
  }

  Future<StoreProfile> _updateStoreProfileDirect({
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

  Future<StoreProfile> _updateStoreProfileOffline({
    required String storeName,
    required String address,
    required String phone,
    required String name,
    required String email,
  }) async {
    final profile = StoreProfile(
      store: storeName.trim(),
      address: address.trim(),
      phone: phone.trim(),
      name: name.trim(),
      email: email.trim(),
    );
    await localCache.setCachedStoreProfile(profile.toJson());

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'update_store_profile',
      'payload': {
        'storeName': storeName.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'name': name.trim(),
        'email': email.trim(),
      },
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
    return profile;
  }

  /// Updates store profile
  Future<StoreProfile> updateStoreProfile({
    required String storeName,
    required String address,
    required String phone,
    required String name,
    required String email,
  }) async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      return _updateStoreProfileOffline(
        storeName: storeName,
        address: address,
        phone: phone,
        name: name,
        email: email,
      );
    }

    try {
      final profile = await _updateStoreProfileDirect(
        storeName: storeName,
        address: address,
        phone: phone,
        name: name,
        email: email,
      );
      await localCache.setCachedStoreProfile(profile.toJson());
      return profile;
    } catch (e) {
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      if (reallyOffline) {
        return _updateStoreProfileOffline(
          storeName: storeName,
          address: address,
          phone: phone,
          name: name,
          email: email,
        );
      }
      rethrow;
    }
  }

  /// Drains the pending owner actions queue by replaying each queued entry
  /// through its existing individual REST method when online.
  Future<bool> processPendingOwnerActions() async {
    final queue = localCache.getPendingOwnerActionsQueue();
    if (queue.isEmpty) return true;

    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) return false;

    AppLogger.log(
      _tag,
      'processPendingOwnerActions(): processing ${queue.length} action(s)',
    );

    final completedIds = <String>{};
    final updatedQueue = <Map<String, dynamic>>[];
    final newlyDeadLettered = <Map<String, dynamic>>[];
    final idMap = <String, String>{};
    var allSuccess = true;

    for (final action in queue) {
      final actionId = action['clientActionId']?.toString() ?? '';
      final type = action['type']?.toString() ?? '';
      final payload = Map<String, dynamic>.from(
        action['payload'] as Map? ?? {},
      );
      var failCount = (action['failCount'] as num?)?.toInt() ?? 0;

      try {
        switch (type) {
          case 'create_expense':
            final localId = payload['localId']?.toString();
            final serverExpense = await _createExpenseDirect(
              title: payload['title']?.toString() ?? '',
              category: payload['category']?.toString() ?? 'Operations',
              amount: (payload['amount'] as num?)?.toInt() ?? 0,
              due: payload['due']?.toString() ?? '',
              monthly: payload['monthly'] == true,
              outletHeader: action.containsKey('outletId')
                  ? (action['outletId'] as String? ?? kNoOutletHeader)
                  : null,
            );
            if (localId != null && localId.isNotEmpty) {
              idMap[localId] = serverExpense.id;
              final cached = localCache.getCachedExpenses() ?? [];
              final idx = cached.indexWhere(
                (e) => e['id']?.toString() == localId,
              );
              if (idx != -1) {
                cached[idx] = serverExpense.toJson();
              } else {
                cached.insert(0, serverExpense.toJson());
              }
              await localCache.setCachedExpenses(cached);
            }
            break;

          case 'mark_expense_paid':
            final rawId = payload['expenseId']?.toString() ?? '';
            final resolvedId = idMap[rawId] ?? rawId;
            await _markExpensePaidDirect(resolvedId);
            final cached = localCache.getCachedExpenses() ?? [];
            final idx = cached.indexWhere(
              (e) =>
                  e['id']?.toString() == resolvedId ||
                  e['id']?.toString() == rawId,
            );
            if (idx != -1) {
              cached[idx] = {
                ...cached[idx],
                'paid': DateTime.now().toIso8601String(),
              };
              await localCache.setCachedExpenses(cached);
            }
            break;

          case 'create_staff':
            final localId = payload['localId']?.toString();
            final serverStaff = await _createStaffDirect(
              name: payload['name']?.toString() ?? '',
              username: payload['username']?.toString() ?? '',
              password: payload['password']?.toString() ?? '',
            );
            if (localId != null && localId.isNotEmpty) {
              idMap[localId] = serverStaff.id;
              final cached = localCache.getCachedStaff() ?? [];
              final idx = cached.indexWhere(
                (s) => s['id']?.toString() == localId,
              );
              if (idx != -1) {
                cached[idx] = serverStaff.toJson();
              } else {
                cached.insert(0, serverStaff.toJson());
              }
              await localCache.setCachedStaff(cached);
            }
            break;

          case 'toggle_staff_active':
            final rawId = payload['employeeId']?.toString() ?? '';
            final resolvedId = idMap[rawId] ?? rawId;
            await _toggleStaffActiveDirect(resolvedId);
            break;

          case 'update_staff':
            final rawId = payload['employeeId']?.toString() ?? '';
            final resolvedId = idMap[rawId] ?? rawId;
            final updatedStaff = await _updateStaffDirect(
              employeeId: resolvedId,
              name: payload['name']?.toString() ?? '',
              username: payload['username']?.toString() ?? '',
            );
            final cached = localCache.getCachedStaff() ?? [];
            final idx = cached.indexWhere(
              (s) =>
                  s['id']?.toString() == resolvedId ||
                  s['id']?.toString() == rawId,
            );
            if (idx != -1) {
              cached[idx] = updatedStaff.toJson();
              await localCache.setCachedStaff(cached);
            }
            break;

          case 'toggle_payment_method':
            final rawId = payload['id']?.toString() ?? '';
            final resolvedId = idMap[rawId] ?? rawId;
            await _togglePaymentMethodDirect(
              resolvedId,
              payload['active'] == true,
            );
            final cached = localCache.getCachedPaymentMethods() ?? [];
            final idx = cached.indexWhere(
              (m) =>
                  m['id']?.toString() == resolvedId ||
                  m['id']?.toString() == rawId,
            );
            if (idx != -1) {
              cached[idx] = {
                ...cached[idx],
                'active': payload['active'] == true,
              };
              await localCache.setCachedPaymentMethods(cached);
            }
            break;

          case 'update_store_profile':
            final serverProfile = await _updateStoreProfileDirect(
              storeName: payload['storeName']?.toString() ?? '',
              address: payload['address']?.toString() ?? '',
              phone: payload['phone']?.toString() ?? '',
              name: payload['name']?.toString() ?? '',
              email: payload['email']?.toString() ?? '',
            );
            await localCache.setCachedStoreProfile(serverProfile.toJson());
            break;

          default:
            // Legacy queued actions (e.g. create/rename_payment_method) hit this branch to be logged and dropped.
            AppLogger.log(
              _tag,
              'processPendingOwnerActions: unknown action type $type',
            );
        }

        completedIds.add(actionId);
      } catch (e) {
        AppLogger.log(
          _tag,
          'processPendingOwnerActions: failed action $type ($actionId)',
          error: e,
        );
        final offlineNow = await ConnectivityService.instance.checkIsOffline();
        if (offlineNow) {
          allSuccess = false;
          updatedQueue.add(action);
          break;
        }

        failCount++;
        final updatedAction = {
          ...action,
          'failCount': failCount,
          'lastError': e.toString(),
        };
        if (failCount >= 3) {
          newlyDeadLettered.add(updatedAction);
        } else {
          updatedQueue.add(updatedAction);
        }
        allSuccess = false;
      }
    }

    final freshQueue = localCache.getPendingOwnerActionsQueue();
    final remaining = <Map<String, dynamic>>[];
    for (final a in freshQueue) {
      final id = a['clientActionId']?.toString();
      if (id != null && completedIds.contains(id)) {
        continue;
      }
      final matchingUpdated = updatedQueue.firstWhere(
        (u) => u['clientActionId'] == id,
        orElse: () => a,
      );
      if (!newlyDeadLettered.any((d) => d['clientActionId'] == id)) {
        remaining.add(matchingUpdated);
      }
    }

    await localCache.setPendingOwnerActionsQueue(remaining);

    if (newlyDeadLettered.isNotEmpty) {
      final currentDeadLetter = localCache.getDeadLetterOwnerActionsQueue();
      await localCache.setDeadLetterOwnerActionsQueue([
        ...currentDeadLetter,
        ...newlyDeadLettered,
      ]);
    }

    return allSuccess;
  }

  /// Revives dead-lettered owner actions for retry upon user tap
  Future<void> reviveDeadLetterQueue() async {
    final deadLetter = localCache.getDeadLetterOwnerActionsQueue();
    if (deadLetter.isEmpty) return;
    AppLogger.log(
      _tag,
      'reviveDeadLetterQueue(): reviving ${deadLetter.length} owner action(s)',
    );
    final revived = deadLetter.map((a) => {...a, 'failCount': 0}).toList();
    final pending = localCache.getPendingOwnerActionsQueue();
    await localCache.setPendingOwnerActionsQueue([...pending, ...revived]);
    await localCache.setDeadLetterOwnerActionsQueue([]);
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
