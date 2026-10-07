import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/core/utils/idempotency.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/models/outlet_rollup_model.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/models/subscription_invoice_model.dart';
import 'package:myshop/features/owner/data/models/store_profile_model.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';

const _tag = 'OWNER_REPO';

/// A write the repository refuses to make (rather than guess), with a message
/// that is safe to show the owner as it is.
class OwnerRefusedException implements Exception {
  final String message;
  OwnerRefusedException(this.message);

  @override
  String toString() => message;
}

class OwnerRepository {
  /// True when the most recent owner write was only queued for later (the
  /// device or the connection was down), so the UI can say "saved offline"
  /// instead of "updated". Static so test doubles need no support for it.
  static bool lastWriteQueued = false;

  final ApiClient apiClient;
  final LocalCacheService localCache;
  final SecureStorageService secureStorage;

  OwnerRepository({
    ApiClient? apiClient,
    LocalCacheService? localCache,
    SecureStorageService? secureStorage,
  }) : apiClient = apiClient ?? ApiClient(),
       localCache = localCache ?? LocalCacheService(),
       secureStorage = secureStorage ?? SecureStorageService();

  String get _invoicesCacheKey =>
      'subscription_invoices::${localCache.getActiveStoreId()}';

  String get _planCacheKey =>
      'subscription_plan::${localCache.getActiveStoreId()}';

  /// The billing terms last sent by the server; null before the first load
  /// or when the server did not send them.
  SubscriptionPlan? getCachedSubscriptionPlan() {
    try {
      final raw = localCache.get(_planCacheKey);
      if (raw is! Map) return null;
      return SubscriptionPlan.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  /// What the phone last saw of the billing history; empty when never loaded.
  List<SubscriptionInvoice> getCachedSubscriptionInvoices() {
    try {
      final raw = localCache.get(_invoicesCacheKey);
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          SubscriptionInvoice.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The owner's platform billing history, newest first. A failed request
  /// throws; callers keep showing [getCachedSubscriptionInvoices].
  Future<List<SubscriptionInvoice>> listSubscriptionInvoices() async {
    final response = await apiClient.get(ApiEndpoints.subscriptionInvoices);
    final rows = response is Map ? response['invoices'] : null;
    if (rows is! List) throw Exception('Could not load billing history');
    final invoices = [
      for (final row in rows)
        SubscriptionInvoice.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    final plan = response['plan'];
    try {
      await localCache.put(_invoicesCacheKey, [
        for (final i in invoices) i.toJson(),
      ]);
      if (plan is Map) {
        await localCache.put(
          _planCacheKey,
          SubscriptionPlan.fromJson(Map<String, dynamic>.from(plan)).toJson(),
        );
      }
    } catch (e) {
      AppLogger.log('OWNER', 'could not cache billing history', error: e);
    }
    return invoices;
  }

  /// The invoice as the server renders it (the same PDF the web shows).
  Future<Uint8List> getSubscriptionInvoicePdf(int invoiceSeq) async {
    final res = await apiClient.getRaw(
      ApiEndpoints.subscriptionInvoicePdf(invoiceSeq),
    );
    if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) return res.bodyBytes;
    throw Exception('Could not load the invoice');
  }

  /// Reads dashboard metrics from the local cache only — no network call.
  DashboardMetrics? getCachedDashboardMetricsSync() {
    try {
      final cached = localCache.getCachedDashboardMetrics();
      if (cached == null) return null;
      return DashboardMetrics.fromJson(cached);
    } catch (_) {
      return null;
    }
  }

  /// The scope (an outlet id, [LocalCacheService.allScope], or 'none') and
  /// store the active selection points at right now. Captured before a
  /// request so its reply is stored where it was asked for, even if the
  /// owner switches outlet while it is in flight.
  ({String? store, String scope}) _captureScope() => (
    store: localCache.getActiveStoreId(),
    scope:
        localCache.getActiveOutletId() ??
        (localCache.isAllOutletsScope() ? LocalCacheService.allScope : 'none'),
  );

  /// Same store as when [cap] was taken (an outlet switch is fine — the write
  /// goes to the captured outlet's own cache — but another store is not).
  bool _sameStore(({String? store, String scope}) cap) =>
      localCache.getActiveStoreId() == cap.store;

  /// The outlet id an owner action is queued under; null for the combined /
  /// no-outlet view.
  static String? _actionOutletId(String scope) =>
      scope == LocalCacheService.allScope || scope == 'none' ? null : scope;

  /// True for failures that mean "could not reach the server" (as opposed to
  /// the server answering with an error).
  static bool _isConnectionFailure(Object e) {
    if (e is TimeoutException) return true;
    if (e is DioException) {
      return e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
    }
    return e is ApiException && e is! AuthException && e.statusCode == null;
  }

  static bool _isAccessFailure(Object e) =>
      e is ApiException && (e.statusCode == 401 || e.statusCode == 403);

  /// A write that failed should be queued instead of reported when the device
  /// is offline or the connection itself failed (Wi-Fi without internet).
  Future<bool> _shouldQueue(Object e) async =>
      _isConnectionFailure(e) ||
      await ConnectivityService.instance.checkIsOffline();

  static String _isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The dashboard's default period: the current month (month-to-date) in daily
  /// buckets. This aligns with the dashboard cards' default selection so they
  /// render immediately from cache offline on first open.
  static ({String from, String to, String granularity}) _defaultRange() {
    final now = DateTime.now();
    return (
      from: _isoDay(DateTime(now.year, now.month, 1)),
      to: _isoDay(now),
      granularity: 'day',
    );
  }

  /// The dashboard's default (month-to-date, daily) metrics — the one
  /// request that is cached.
  Future<DashboardMetrics> getDefaultDashboardMetrics() {
    final r = _defaultRange();
    return getDashboardMetrics(
      from: r.from,
      to: r.to,
      granularity: r.granularity,
    );
  }

  /// Fetches aggregated metrics for dashboard & reports
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
    String? granularity,
  }) async {
    // A bare request means the default period. The server answers a bare one
    // in a legacy shape (no cashRange, interval bars), which must never be
    // cached or shown as the 30-day default.
    if ((from == null || from.isEmpty) &&
        (to == null || to.isEmpty) &&
        (granularity == null || granularity.isEmpty)) {
      final r = _defaultRange();
      from = r.from;
      to = r.to;
      granularity = r.granularity;
    }
    final query = <String, String>{};
    if (from != null && from.isNotEmpty) query['from'] = from;
    if (to != null && to.isNotEmpty) query['to'] = to;
    if (granularity != null && granularity.isNotEmpty) {
      query['granularity'] = granularity;
    }
    final cap = _captureScope();
    final outletId = localCache.getActiveOutletId();
    if (outletId != null && !localCache.isAllOutletsScope()) {
      query['outletId'] = outletId;
    }
    // Only the default period is cached, so only it may fall back to the
    // cache; another period's figures must never be served from it.
    final isDefault = _isDefaultDashboardRequest(query);

    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      final cached = isDefault
          ? localCache.getCachedDashboardMetricsForScope(cap.scope)
          : null;
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

    final uri = Uri.parse(ApiEndpoints.dashboard)
        .replace(queryParameters: query.isEmpty ? null : query);

    final hasCache = localCache.getCachedDashboardMetrics() != null;
    final startedSync = !hasCache;
    if (startedSync) {
      SyncManager.instance.startSync('Fetching latest from cloud...');
    }
    try {
      final response = await apiClient.get(uri.toString());
      if (response is! Map) {
        // e.g. a captive-portal page: not data, and never cached.
        throw Exception('Unexpected dashboard response');
      }
      final metrics = DashboardMetrics.fromJson(
        Map<String, dynamic>.from(response),
      );
      if (isDefault && _sameStore(cap)) {
        await localCache.setCachedDashboardMetricsForScope(
          cap.scope,
          metrics.toJson(),
        );
      }
      SyncManager.instance.completeSync();
      return metrics;
    } catch (e) {
      if (_isAccessFailure(e)) rethrow;
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      final cached = isDefault && _sameStore(cap)
          ? localCache.getCachedDashboardMetricsForScope(cap.scope)
          : null;
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
    } finally {
      if (startedSync && SyncManager.instance.value.isSyncing) {
        SyncManager.instance.setError('Could not refresh dashboard');
      }
    }
  }

  /// Metrics for one card's own period. Never falls back to the cache — it
  /// only holds the default period, and serving it under another period's
  /// label would be wrong — so any failure is thrown for the card to show.
  Future<DashboardMetrics> getPeriodMetrics({
    required String from,
    required String to,
    required String granularity,
  }) async {
    if (await ConnectivityService.instance.checkIsOffline()) {
      throw Exception('No network connection');
    }
    final query = <String, String>{
      'from': from,
      'to': to,
      'granularity': granularity,
    };
    final outletId = localCache.getActiveOutletId();
    if (outletId != null && !localCache.isAllOutletsScope()) {
      query['outletId'] = outletId;
    }
    final uri = Uri.parse(ApiEndpoints.dashboard)
        .replace(queryParameters: query);
    final response = await apiClient.get(uri.toString());
    if (response is! Map) throw Exception('Dashboard not loaded');
    return DashboardMetrics.fromJson(Map<String, dynamic>.from(response));
  }

  /// Per-outlet daily performance. This is deliberately online-only and is
  /// never written into the dashboard cache.
  Future<List<OutletRollup>> getOutletRollups({
    required String from,
    required String to,
  }) async {
    if (await ConnectivityService.instance.checkIsOffline()) {
      throw Exception('No network connection');
    }
    final uri = Uri.parse(ApiEndpoints.dashboardRollups)
        .replace(queryParameters: {'from': from, 'to': to});
    final response = await apiClient.get(uri.toString());
    if (response is! List) throw Exception('Outlet rollups not loaded');
    return [
      for (final row in response)
        if (row is Map) OutletRollup.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  /// The request the dashboard opens with: the current month (month-to-date)
  /// in daily buckets. A bare request (no range) or a custom range that merely
  /// uses daily buckets is not it — the response shapes differ.
  static bool _isDefaultDashboardRequest(Map<String, String> query) {
    final r = _defaultRange();
    return query['granularity'] == r.granularity &&
        query['from'] == r.from &&
        query['to'] == r.to;
  }

  /// Sign-in sync of one named scope's default-period dashboard (an outlet id,
  /// or [LocalCacheService.allScope]) into that scope's own cache, without
  /// touching the active scope or the sync banner. Throws on failure.
  Future<void> syncDashboardForScope(String scope) async {
    final r = _defaultRange();
    final query = <String, String>{
      'from': r.from,
      'to': r.to,
      'granularity': r.granularity,
      if (scope != LocalCacheService.allScope) 'outletId': scope,
    };
    final uri = Uri.parse(ApiEndpoints.dashboard)
        .replace(queryParameters: query);
    final response = await apiClient.get(
      uri.toString(),
      headers: {
        'X-Outlet-Id': scope == LocalCacheService.allScope
            ? kNoOutletHeader
            : scope,
      },
    );
    if (response is! Map) throw Exception('Dashboard not loaded');
    final metrics = DashboardMetrics.fromJson(
      Map<String, dynamic>.from(response),
    );
    await localCache.setCachedDashboardMetricsForScope(scope, metrics.toJson());
  }

  /// Same as [syncDashboardForScope], for the expenses list.
  Future<void> syncExpensesForScope(String scope) async {
    final response = await apiClient.get(
      ApiEndpoints.expenses,
      headers: {
        'X-Outlet-Id': scope == LocalCacheService.allScope
            ? kNoOutletHeader
            : scope,
      },
    );
    if (response is! List) throw Exception('Expenses not loaded');
    final expenses = _withQueuedExpenseChanges(
      scope,
      response
          .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
    await localCache.setCachedExpensesForScope(
      scope,
      expenses.map((e) => e.toJson()).toList(),
    );
    _completeExpenseRefresh();
  }

  void _completeExpenseRefresh() {
    final syncManager = SyncManager.instance;
    if (syncManager.value.hasError) {
      syncManager.clearError('Could not refresh expenses');
    } else {
      syncManager.completeSync();
    }
  }

  /// Reads expenses from the local cache only — no network call.
  List<Expense>? getCachedExpensesSync() {
    try {
      final cached = localCache.getCachedExpenses();
      if (cached == null) return null;
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
      if (cached != null) {
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

    final cap = _captureScope();
    var startedSync = false;
    try {
      final hasCache = localCache.getCachedExpenses() != null;
      if (!hasCache) {
        startedSync = true;
        SyncManager.instance.startSync('Fetching latest from cloud...');
      }
      final response = await apiClient.get(ApiEndpoints.expenses);
      // Not a list (e.g. a captive-portal page): an error, not "no expenses".
      if (response is! List) throw Exception('Unexpected expenses response');
      final expenses = _withQueuedExpenseChanges(
        cap.scope,
        response
            .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
      if (_sameStore(cap)) {
        await localCache.setCachedExpensesForScope(
          cap.scope,
          expenses.map((e) => e.toJson()).toList(),
        );
      }
      _completeExpenseRefresh();
      return expenses;
    } catch (e) {
      if (_isAccessFailure(e)) rethrow;
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      final cached = _sameStore(cap)
          ? localCache.getCachedExpensesForScope(cap.scope)
          : null;
      if (cached != null) {
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
    } finally {
      if (startedSync && SyncManager.instance.value.isSyncing) {
        SyncManager.instance.setError('Could not refresh expenses');
      }
    }
  }

  /// Direct online API call for creating expense
  Future<Expense> _createExpenseDirect({
    required String title,
    required String category,
    required int amount,
    required String due,
    bool monthly = false,
    String? idempotencyKey,
    String? outletHeader,
    String? outletId,
    bool orgWide = false,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : IdempotencyKeyGenerator.generate();
    Map<String, String>? headers;
    final body = <String, dynamic>{
      'title': title.trim(),
      'category': category.trim(),
      'amount': amount,
      'due': due,
      'monthly': monthly,
      'idempotencyKey': key,
    };
    if (orgWide) {
      headers = {'X-Outlet-Id': kNoOutletHeader};
    } else if (outletId != null && outletId.isNotEmpty) {
      body['outletId'] = outletId;
      headers = {'X-Outlet-Id': outletHeader ?? outletId};
    } else if (outletHeader != null) {
      headers = {'X-Outlet-Id': outletHeader};
    }

    final response = await apiClient.post(
      ApiEndpoints.expenses,
      headers: headers,
      body: body,
    );
    return Expense.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<Expense> _createExpenseOffline({
    required String title,
    required String category,
    required int amount,
    required String due,
    bool monthly = false,
    required String idempotencyKey,
    required ({String? store, String scope}) cap,
    String? outletId,
    bool orgWide = false,
  }) async {
    lastWriteQueued = true;
    final localId = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
    final targetOutletId = orgWide
        ? null
        : (outletId ?? _actionOutletId(cap.scope));
    final localExpense = Expense(
      id: localId,
      outletId: targetOutletId,
      title: title.trim(),
      category: category.trim(),
      amount: amount,
      due: due,
      monthly: monthly,
    );
    await _patchCachedExpenses(
      cap,
      ensureCurrent: true,
      (scope, cached) => _placeExpense(scope, cached, localExpense),
    );

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'create_expense',
      'outletId': orgWide ? null : (outletId ?? _actionOutletId(cap.scope)),
      'scope': cap.scope,
      'payload': {
        'localId': localId,
        'title': title.trim(),
        'category': category.trim(),
        'amount': amount,
        'due': due,
        'monthly': monthly,
        'idempotencyKey': idempotencyKey,
        if (outletId != null && outletId.isNotEmpty) 'outletId': outletId,
        if (orgWide) 'orgWide': true,
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
    String? idempotencyKey,
    String? outletId,
    bool orgWide = false,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : IdempotencyKeyGenerator.generate();
    lastWriteQueued = false;
    final cap = _captureScope();
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      return _createExpenseOffline(
        title: title,
        category: category,
        amount: amount,
        due: due,
        monthly: monthly,
        idempotencyKey: key,
        cap: cap,
        outletId: outletId,
        orgWide: orgWide,
      );
    }

    try {
      final expense = await _createExpenseDirect(
        title: title,
        category: category,
        amount: amount,
        due: due,
        monthly: monthly,
        idempotencyKey: key,
        outletId: outletId,
        orgWide: orgWide,
      );
      final placed = _withRequestedOutlet(
        expense,
        orgWide ? null : (outletId ?? _actionOutletId(cap.scope)),
      );
      await _patchCachedExpenses(
        cap,
        ensureCurrent: true,
        (scope, cached) => _placeExpense(scope, cached, placed),
      );
      return expense;
    } catch (e) {
      if (await _shouldQueue(e)) {
        return _createExpenseOffline(
          title: title,
          category: category,
          amount: amount,
          due: due,
          monthly: monthly,
          idempotencyKey: key,
          cap: cap,
          outletId: outletId,
          orgWide: orgWide,
        );
      }
      rethrow;
    }
  }

  /// Updates an existing expense (online only)
  Future<void> updateExpense(
    String id, {
    required String title,
    required String category,
    required int amount,
    required String due,
    String? outletId,
  }) async {
    lastWriteQueued = false;
    _requireSyncedExpense(id);
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      throw OwnerRefusedException('This needs a connection');
    }

    final body = <String, dynamic>{
      'title': title.trim(),
      'category': category.trim(),
      'amount': amount,
      'due': due,
      if (outletId != null && outletId.isNotEmpty) 'outletId': outletId,
    };

    final cap = _captureScope();
    final response = await apiClient.put(
      ApiEndpoints.expenseById(id),
      body: body,
    );
    final updated = Expense.fromJson(
      Map<String, dynamic>.from(response as Map),
    );

    // An outlet's list holds only its own bills; the combined views (All, or
    // no outlet selected) hold every bill.
    await _patchCachedExpenses(
      cap,
      (scope, cached) => _placeExpense(scope, cached, updated),
    );
  }

  /// Deletes an expense (online only)
  Future<void> deleteExpense(String id) async {
    lastWriteQueued = false;
    _requireSyncedExpense(id);
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      throw OwnerRefusedException('This needs a connection');
    }

    final cap = _captureScope();
    await apiClient.delete(ApiEndpoints.expenseById(id));

    await _patchCachedExpenses(cap, (scope, cached) {
      final before = cached.length;
      cached.removeWhere((e) => e['id']?.toString() == id);
      return cached.length != before;
    });
  }

  /// A bill created offline has no server id yet, so the server can't edit or
  /// delete it; the owner can once it has synced.
  void _requireSyncedExpense(String id) {
    if (Expense.isUnsyncedId(id)) {
      throw OwnerRefusedException(
        'This bill is still syncing. Try again in a moment.',
      );
    }
  }

  /// Applies [patch] to the cached expense list of every scope of the active
  /// store that has one (All, each allowed outlet, and the current scope), and
  /// saves the lists it changed. A scope that was never cached is left alone,
  /// so it is not made to look synced.
  /// With [ensureCurrent] the current scope's list is created if it doesn't
  /// exist yet, as a new bill is always shown where it was made.
  Future<void> _patchCachedExpenses(
    ({String? store, String scope}) cap,
    bool Function(String scope, List<Map<String, dynamic>> cached) patch, {
    bool ensureCurrent = false,
  }) async {
    if (!_sameStore(cap)) return;
    final scopes = <String>{
      cap.scope,
      LocalCacheService.allScope,
      for (final o in localCache.getAllowedOutlets() ?? const [])
        if (o['id']?.toString().isNotEmpty == true) o['id'].toString(),
    };
    for (final scope in scopes) {
      var cached = localCache.getCachedExpensesForScope(scope);
      if (cached == null) {
        if (!(ensureCurrent && scope == cap.scope)) continue;
        cached = <Map<String, dynamic>>[];
      }
      if (patch(scope, cached)) {
        await localCache.setCachedExpensesForScope(scope, cached);
      }
    }
  }

  /// The server names a bill's outlet in its reply; if a reply ever leaves it
  /// out, fall back to the outlet the request was made for so the bill is still
  /// cached where it belongs.
  Expense _withRequestedOutlet(Expense row, String? requestedOutletId) =>
      row.outletId != null || requestedOutletId == null
      ? row
      : Expense.fromJson({...row.toJson(), 'outletId': requestedOutletId});

  /// Puts [row] into one scope's cached list if it belongs there, or takes it
  /// out if it doesn't. An outlet's list holds only that outlet's bills; the
  /// combined views (All, or no outlet selected) hold every bill. [replacingId]
  /// is the placeholder a queued bill had before the server gave it an id.
  /// Returns whether the list changed.
  bool _placeExpense(
    String scope,
    List<Map<String, dynamic>> cached,
    Expense row, {
    String? replacingId,
  }) {
    final belongs = _actionOutletId(scope) == null || row.outletId == scope;
    var at = 0;
    var changed = false;
    for (final id in {?replacingId, row.id}) {
      final i = cached.indexWhere((e) => e['id']?.toString() == id);
      if (i != -1) {
        at = i;
        cached.removeAt(i);
        changed = true;
      }
    }
    if (belongs) {
      cached.insert(at.clamp(0, cached.length), row.toJson());
      changed = true;
    }
    return changed;
  }

  /// Marks the bill (under any of [ids]) paid in every cached list that holds
  /// it, so the combined and per-outlet views agree.
  Future<void> _setCachedExpensePaid(
    ({String? store, String scope}) cap,
    Set<String> ids,
    String paidDate,
  ) => _patchCachedExpenses(cap, (scope, cached) {
    var changed = false;
    for (var i = 0; i < cached.length; i++) {
      if (ids.contains(cached[i]['id']?.toString())) {
        cached[i] = {...cached[i], 'paid': paidDate};
        changed = true;
      }
    }
    return changed;
  });

  /// A refresh brings the server's list, which doesn't know about changes
  /// still waiting in the queue; put those back on top so a bill marked paid
  /// (or created) offline doesn't flip back until the server has really taken
  /// it.
  List<Expense> _withQueuedExpenseChanges(String scope, List<Expense> server) {
    final list = [for (final e in server) e.toJson()];
    for (final action in localCache.getPendingOwnerActionsQueue()) {
      final payload = Map<String, dynamic>.from(
        action['payload'] as Map? ?? {},
      );
      switch (action['type']) {
        case 'mark_expense_paid':
          final id = payload['expenseId']?.toString();
          final paid = payload['paidDate']?.toString();
          if (id == null || paid == null) continue;
          for (var i = 0; i < list.length; i++) {
            if (list[i]['id']?.toString() == id) {
              list[i] = {...list[i], 'paid': paid};
            }
          }
        case 'create_expense':
          final localId = payload['localId']?.toString();
          if (localId == null || list.any((e) => e['id'] == localId)) continue;
          final outletId = payload['orgWide'] == true
              ? null
              : (payload['outletId']?.toString() ??
                    action['outletId'] as String?);
          if (_actionOutletId(scope) != null && outletId != scope) continue;
          list.insert(
            0,
            Expense(
              id: localId,
              outletId: outletId,
              title: payload['title']?.toString() ?? '',
              category: payload['category']?.toString() ?? 'Operations',
              amount: (payload['amount'] as num?)?.toInt() ?? 0,
              due: payload['due']?.toString() ?? '',
              monthly: payload['monthly'] == true,
            ).toJson(),
          );
      }
    }
    return [for (final e in list) Expense.fromJson(e)];
  }

  Future<void> _markExpensePaidDirect(
    String expenseId, {
    String? paidDate,
    String? outletHeader,
  }) async {
    final body = <String, dynamic>{
      if (paidDate != null && paidDate.isNotEmpty) 'paidDate': paidDate,
    };
    await apiClient.post(
      ApiEndpoints.markExpensePaid(expenseId),
      headers: outletHeader != null ? {'X-Outlet-Id': outletHeader} : null,
      body: body,
    );
  }

  Future<void> _markExpensePaidOffline(
    String expenseId,
    ({String? store, String scope}) cap, {
    String? paidDate,
  }) async {
    lastWriteQueued = true;
    final effectivePaidDate = paidDate ?? DateFormatter.todayIsoDateString();
    await _setCachedExpensePaid(cap, {expenseId}, effectivePaidDate);

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'mark_expense_paid',
      'outletId': _actionOutletId(cap.scope),
      'scope': cap.scope,
      'payload': {'expenseId': expenseId, 'paidDate': effectivePaidDate},
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
  }

  /// Marks an expense paid
  Future<void> markExpensePaid(String expenseId, {String? paidDate}) async {
    lastWriteQueued = false;
    final cap = _captureScope();
    final effectivePaidDate = paidDate ?? DateFormatter.todayIsoDateString();
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      await _markExpensePaidOffline(
        expenseId,
        cap,
        paidDate: effectivePaidDate,
      );
      return;
    }

    try {
      await _markExpensePaidDirect(expenseId, paidDate: paidDate);
      await _setCachedExpensePaid(cap, {expenseId}, effectivePaidDate);
    } catch (e) {
      if (await _shouldQueue(e)) {
        await _markExpensePaidOffline(
          expenseId,
          cap,
          paidDate: effectivePaidDate,
        );
        return;
      }
      rethrow;
    }
  }

  /// Reads staff from the local cache only — no network call.
  List<StaffMember>? getCachedStaffSync() {
    try {
      final cached = localCache.getCachedStaff();
      if (cached == null) return null;
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
      if (cached != null) {
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

    var startedSync = false;
    try {
      final hasCache = localCache.getCachedStaff() != null;
      if (!hasCache) {
        startedSync = true;
        SyncManager.instance.startSync('Fetching latest from cloud...');
      }
      final response = await apiClient.get(ApiEndpoints.employees);
      // Not a list (e.g. a captive-portal page): an error, not "no staff".
      if (response is! List) throw Exception('Unexpected staff response');
      final staff = response
          .map((s) => StaffMember.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
      await localCache.setCachedStaff(staff.map((s) => s.toJson()).toList());
      SyncManager.instance.completeSync();
      return staff;
    } catch (e) {
      if (_isAccessFailure(e)) rethrow;
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      final cached = localCache.getCachedStaff();
      if (cached != null) {
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
    } finally {
      if (startedSync && SyncManager.instance.value.isSyncing) {
        SyncManager.instance.setError('Could not refresh staff');
      }
    }
  }

  Future<StaffMember> _createStaffDirect({
    required String name,
    required String phone,
    required String password,
    String? idempotencyKey,
    List<String>? outletIds,
    String? defaultOutletId,
  }) async {
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : IdempotencyKeyGenerator.generate();
    final response = await apiClient.post(
      ApiEndpoints.employees,
      body: {
        'name': name.trim(),
        'phone': phone.trim(),
        'password': password,
        'active': true,
        'idempotencyKey': key,
        'outlets': ?outletIds,
        'defaultOutletId': ?defaultOutletId,
      },
    );
    return StaffMember.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Adds a new staff member with a generated or chosen temporary password
  Future<StaffMember> createStaff({
    required String name,
    required String phone,
    required String password,
    String? idempotencyKey,
    List<String>? outletIds,
    String? defaultOutletId,
  }) async {
    lastWriteQueued = false;
    final key = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : IdempotencyKeyGenerator.generate();
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      throw Exception('Adding staff needs an internet connection');
    }

    try {
      final staff = await _createStaffDirect(
        name: name,
        phone: phone,
        password: password,
        idempotencyKey: key,
        outletIds: outletIds,
        defaultOutletId: defaultOutletId,
      );
      final cached = localCache.getCachedStaff() ?? [];
      cached.insert(0, staff.toJson());
      await localCache.setCachedStaff(cached);
      return staff;
    } catch (e) {
      if (await _shouldQueue(e)) {
        throw Exception('Adding staff needs an internet connection');
      }
      rethrow;
    }
  }

  Future<void> _toggleStaffActiveDirect(String employeeId) async {
    await apiClient.post(
      ApiEndpoints.toggleEmployeeActive(employeeId),
      body: {},
    );
  }

  /// Explicit desired state makes queued replay idempotent. The endpoint
  /// accepts active alone, so a stale cached name/phone cannot overwrite an
  /// edit made on another device while this action waited offline.
  Future<void> _setStaffActiveDirect({
    required String employeeId,
    required bool active,
  }) async {
    await apiClient.put(
      ApiEndpoints.employeeDetail(employeeId),
      body: {'active': active},
    );
  }

  Future<void> _setStaffActiveOffline({
    required String employeeId,
    required bool active,
  }) async {
    lastWriteQueued = true;
    final cached = localCache.getCachedStaff() ?? [];
    final idx = cached.indexWhere((s) => s['id']?.toString() == employeeId);
    if (idx != -1) {
      cached[idx] = {...cached[idx], 'active': active};
      await localCache.setCachedStaff(cached);
    }

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'set_staff_active',
      'payload': {'employeeId': employeeId, 'active': active},
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
  }

  /// Fetches the staff list from the server, refreshes the cache with it and
  /// returns the row for [employeeId] (null when absent).
  Future<Map<String, dynamic>?> _fetchStaffRow(String employeeId) async {
    final response = await apiClient.get(ApiEndpoints.employees);
    if (response is! List) throw Exception('Unexpected staff response');
    final rows = [
      for (final r in response)
        if (r is Map) Map<String, dynamic>.from(r),
    ];
    await localCache.setCachedStaff(rows);
    for (final r in rows) {
      if (r['id']?.toString() == employeeId) return r;
    }
    return null;
  }

  static final _staffUnknown = OwnerRefusedException(
    'Could not confirm this employee\'s current details — refresh the staff '
    'list and try again',
  );

  /// The employee's cached row, or (online only) the server's when the cache
  /// has none. Null when it cannot be determined.
  Future<Map<String, dynamic>?> _staffRow(
    String employeeId, {
    required bool online,
  }) async {
    final cached = localCache.getCachedStaff() ?? [];
    final idx = cached.indexWhere((s) => s['id']?.toString() == employeeId);
    if (idx != -1) return cached[idx];
    return online ? _fetchStaffRow(employeeId) : null;
  }

  /// Toggles active status of employee
  Future<void> toggleStaffActive(String employeeId) async {
    lastWriteQueued = false;
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    Map<String, dynamic>? row;
    try {
      row = await _staffRow(employeeId, online: !isOffline);
    } catch (e) {
      if (!await _shouldQueue(e)) rethrow;
    }
    // Never guess the current state from a missing row.
    if (row == null) throw _staffUnknown;
    final newActive = row['active'] == false;

    if (isOffline) {
      await _setStaffActiveOffline(employeeId: employeeId, active: newActive);
      return;
    }

    try {
      await _setStaffActiveDirect(employeeId: employeeId, active: newActive);
      final freshCached = localCache.getCachedStaff() ?? [];
      final freshIdx = freshCached.indexWhere(
        (s) => s['id']?.toString() == employeeId,
      );
      if (freshIdx != -1) {
        freshCached[freshIdx] = {...freshCached[freshIdx], 'active': newActive};
        await localCache.setCachedStaff(freshCached);
      }
    } catch (e) {
      if (await _shouldQueue(e)) {
        await _setStaffActiveOffline(employeeId: employeeId, active: newActive);
        return;
      }
      rethrow;
    }
  }

  /// [active] null means "leave the employee's status alone": the PUT still
  /// needs it, so the current one is read from the cache — or, when [fresh]
  /// is set (a replay long after the cache was written) or the row isn't
  /// cached, from the server. If it can't be determined nothing is sent.
  Future<StaffMember> _updateStaffDirect({
    required String employeeId,
    required String name,
    required String phone,
    String? password,
    bool? active,
    bool fresh = false,
    List<String>? outletIds,
    String? defaultOutletId,
  }) async {
    if (name.trim().isEmpty || phone.trim().isEmpty) {
      throw ValidationException('Employee name and phone are required');
    }
    if (password != null &&
        password.isNotEmpty &&
        (password.length < 8 || password.length > 128)) {
      throw ValidationException('Password must be 8–128 characters');
    }
    var resolvedActive = active;
    if (resolvedActive == null) {
      final row = fresh
          ? await _fetchStaffRow(employeeId)
          : await _staffRow(employeeId, online: true);
      if (row == null) throw _staffUnknown;
      resolvedActive = row['active'] != false;
    }
    final response = await apiClient.put(
      ApiEndpoints.employeeDetail(employeeId),
      body: {
        'name': name.trim(),
        'phone': phone.trim(),
        'active': resolvedActive,
        if (password?.isNotEmpty == true) 'password': password,
        // Only sent when the owner changed assignments; leaving them out
        // keeps whatever the employee already has.
        'outlets': ?outletIds,
        if (outletIds != null && defaultOutletId != null)
          'defaultOutletId': defaultOutletId,
      },
    );
    return StaffMember.fromJson(Map<String, dynamic>.from(response as Map));
  }

  static List<String>? _stringList(Object? raw) =>
      raw is List ? [for (final v in raw) v.toString()] : null;

  /// Outlet refs for the ids: names from the outlets cached at sign-in, else
  /// the name the employee's row already had, else no name at all (never a
  /// blank one).
  List<Map<String, dynamic>> _outletRefs(
    List<String> ids, {
    List<Map<String, dynamic>> previous = const [],
  }) {
    final known = <String, String>{
      for (final o in previous)
        if ((o['name']?.toString() ?? '').trim().isNotEmpty)
          o['id']?.toString() ?? '': o['name'].toString(),
      for (final o in localCache.getAllowedOutlets() ?? const [])
        if ((o['displayName']?.toString() ?? '').trim().isNotEmpty)
          o['id']?.toString() ?? '': o['displayName'].toString(),
    };
    return [
      for (final id in ids)
        {'id': id, if (known[id] != null) 'name': known[id]},
    ];
  }

  Future<StaffMember> _updateStaffOffline({
    required String employeeId,
    required String name,
    required String phone,
    List<String>? outletIds,
    String? defaultOutletId,
  }) async {
    final cached = localCache.getCachedStaff() ?? [];
    final idx = cached.indexWhere((s) => s['id']?.toString() == employeeId);
    // Without the cached row there is nothing to base the edit on.
    if (idx == -1) throw _staffUnknown;
    lastWriteQueued = true;
    final previousOutlets = [
      for (final o in (cached[idx]['outlets'] as List? ?? const []))
        if (o is Map) Map<String, dynamic>.from(o),
    ];
    final updated = {
      ...cached[idx],
      'name': name.trim(),
      'phone': phone.trim(),
      if (outletIds != null)
        'outlets': _outletRefs(outletIds, previous: previousOutlets),
      if (outletIds != null && defaultOutletId != null)
        'defaultOutletId': defaultOutletId,
    };
    // Outlets changed with no default: the old default no longer applies.
    if (outletIds != null && defaultOutletId == null) {
      updated.remove('defaultOutletId');
    }
    cached[idx] = updated;
    await localCache.setCachedStaff(cached);
    final member = StaffMember.fromJson(updated);

    await localCache.enqueueOwnerAction({
      'clientActionId': 'owner_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'update_staff',
      // No `active`: the replay reads the server's current value, so a
      // stale copy here can't reactivate someone deactivated meanwhile.
      'payload': {
        'employeeId': employeeId,
        'name': name.trim(),
        'phone': phone.trim(),
        'outlets': ?outletIds,
        if (outletIds != null && defaultOutletId != null)
          'defaultOutletId': defaultOutletId,
      },
      'queuedAt': DateTime.now().toIso8601String(),
    });

    SyncEngine.instance.trigger();
    return member;
  }

  /// Updates staff member details. [outletIds] / [defaultOutletId] are only
  /// passed when the owner changed the employee's outlets; null leaves them
  /// as they are.
  Future<StaffMember> updateStaff({
    required String employeeId,
    required String name,
    required String phone,
    String? password,
    List<String>? outletIds,
    String? defaultOutletId,
  }) async {
    lastWriteQueued = false;
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    final changesPassword = password?.isNotEmpty == true;
    if (isOffline) {
      if (changesPassword) {
        throw OwnerRefusedException('This needs a connection');
      }
      return _updateStaffOffline(
        employeeId: employeeId,
        name: name,
        phone: phone,
        outletIds: outletIds,
        defaultOutletId: defaultOutletId,
      );
    }

    try {
      final staff = await _updateStaffDirect(
        employeeId: employeeId,
        name: name,
        phone: phone,
        password: password,
        outletIds: outletIds,
        defaultOutletId: defaultOutletId,
      );
      final cached = localCache.getCachedStaff() ?? [];
      final idx = cached.indexWhere((s) => s['id']?.toString() == employeeId);
      if (idx != -1) {
        cached[idx] = staff.toJson();
        await localCache.setCachedStaff(cached);
      }
      return staff;
    } catch (e) {
      if (changesPassword && await _shouldQueue(e)) {
        throw OwnerRefusedException('This needs a connection');
      }
      if (await _shouldQueue(e)) {
        return _updateStaffOffline(
          employeeId: employeeId,
          name: name,
          phone: phone,
          outletIds: outletIds,
          defaultOutletId: defaultOutletId,
        );
      }
      rethrow;
    }
  }

  /// Reads payment methods from the local cache only — no network call.
  List<StorePaymentMethod>? getCachedPaymentMethodsSync() {
    try {
      final cached = localCache.getCachedPaymentMethods();
      if (cached == null) return null;
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

    var startedSync = false;
    try {
      final hasCache = localCache.getCachedPaymentMethods() != null;
      if (!hasCache) {
        startedSync = true;
        SyncManager.instance.startSync('Fetching latest from cloud...');
      }
      final response = await apiClient.get(ApiEndpoints.paymentMethodsAll);
      // Not a list (e.g. a captive-portal page): an error, not "no methods".
      if (response is! List) {
        throw Exception('Unexpected payment methods response');
      }
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
    } catch (e) {
      if (_isAccessFailure(e)) rethrow;
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
    } finally {
      if (startedSync && SyncManager.instance.value.isSyncing) {
        SyncManager.instance.setError('Could not refresh payment methods');
      }
    }
  }

  Future<void> _togglePaymentMethodDirect(String id, bool active) async {
    await apiClient.patch(
      ApiEndpoints.paymentMethodDetail(id),
      body: {'enabled': active},
    );
  }

  Future<void> _togglePaymentMethodOffline(String id, bool active) async {
    lastWriteQueued = true;
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
    lastWriteQueued = false;
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
      if (await _shouldQueue(e)) {
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

    var startedSync = false;
    try {
      final cachedProfile = localCache.getCachedStoreProfile();
      final hasCache = cachedProfile != null && cachedProfile.isNotEmpty;
      if (!hasCache) {
        startedSync = true;
        SyncManager.instance.startSync('Fetching latest from cloud...');
      }
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
      if (_isAccessFailure(e)) rethrow;
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
    } finally {
      if (startedSync && SyncManager.instance.value.isSyncing) {
        SyncManager.instance.setError('Could not refresh store profile');
      }
    }
  }

  Future<StoreProfile> _updateStoreProfileDirect({
    required String storeName,
    required String address,
    required String phone,
    required String name,
    required String email,
  }) async {
    final response = await apiClient.put(
      ApiEndpoints.profile,
      body: {
        'name': name.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'store': storeName.trim(),
        'address': address.trim(),
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
    lastWriteQueued = true;
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
    lastWriteQueued = false;
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
      if (await _shouldQueue(e)) {
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

  /// Only the server rejecting the action itself (validation, conflict, not
  /// found...) counts towards dead-lettering.
  static bool _countsAsFailure(Object e) {
    if (e is! ApiException || e is AuthException) return false;
    final code = e.statusCode;
    if (code == null || code < 400 || code >= 500) return false;
    return code != 401 && code != 403 && code != 408 && code != 429;
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

    Future<void> rewriteQueuedId(
      String field,
      String localId,
      String serverId,
    ) async {
      for (var j = 0; j < queue.length; j++) {
        final p = Map<String, dynamic>.from(queue[j]['payload'] as Map? ?? {});
        if (p[field]?.toString() == localId) {
          p[field] = serverId;
          queue[j] = {...queue[j], 'payload': p};
        }
      }
      final persisted = localCache.getPendingOwnerActionsQueue();
      var changed = false;
      final rewritten = persisted.map((a) {
        final p = Map<String, dynamic>.from(a['payload'] as Map? ?? {});
        if (p[field]?.toString() == localId) {
          p[field] = serverId;
          changed = true;
          return {...a, 'payload': p};
        }
        return a;
      }).toList();
      if (changed) {
        await localCache.setPendingOwnerActionsQueue(rewritten);
      }
    }

    for (var i = 0; i < queue.length; i++) {
      final action = queue[i];
      final actionId = action['clientActionId']?.toString() ?? '';
      final type = action['type']?.toString() ?? '';
      final payload = Map<String, dynamic>.from(
        action['payload'] as Map? ?? {},
      );
      var failCount = (action['failCount'] as num?)?.toInt() ?? 0;
      // Outlet-scoped actions replay under their OWN outlet, whatever the
      // owner has selected now. Actions queued before this was recorded
      // carry neither and fall back to the current selection.
      final String? actionScope = action['scope'] is String
          ? action['scope'] as String
          : action.containsKey('outletId')
          ? (action['outletId'] as String? ?? LocalCacheService.allScope)
          : null;
      final String? actionHeader = action.containsKey('outletId')
          ? (action['outletId'] as String? ?? kNoOutletHeader)
          : null;

      try {
        switch (type) {
          case 'create_expense':
            final localId = payload['localId']?.toString();
            final payloadOrgWide = payload['orgWide'] == true;
            final payloadOutletId = payload['outletId']?.toString();
            final effectiveOutletId = payloadOrgWide
                ? null
                : (payloadOutletId ?? action['outletId'] as String?);
            final header = payloadOrgWide
                ? kNoOutletHeader
                : (effectiveOutletId ?? actionHeader);
            final serverExpense = await _createExpenseDirect(
              title: payload['title']?.toString() ?? '',
              category: payload['category']?.toString() ?? 'Operations',
              amount: (payload['amount'] as num?)?.toInt() ?? 0,
              due: payload['due']?.toString() ?? '',
              monthly: payload['monthly'] == true,
              idempotencyKey: payload['idempotencyKey']?.toString(),
              outletId: effectiveOutletId,
              orgWide: payloadOrgWide,
              outletHeader: header,
            );
            if (localId != null && localId.isNotEmpty) {
              idMap[localId] = serverExpense.id;
              await rewriteQueuedId('expenseId', localId, serverExpense.id);
              await _patchCachedExpenses(
                (
                  store: localCache.getActiveStoreId(),
                  scope: actionScope ?? _captureScope().scope,
                ),
                ensureCurrent: true,
                (scope, cached) => _placeExpense(
                  scope,
                  cached,
                  _withRequestedOutlet(serverExpense, effectiveOutletId),
                  replacingId: localId,
                ),
              );
            }
            break;

          case 'mark_expense_paid':
            final rawId = payload['expenseId']?.toString() ?? '';
            final resolvedId = idMap[rawId] ?? rawId;
            final payloadPaidDate =
                payload['paidDate']?.toString() ??
                DateFormatter.todayIsoDateString();
            await _markExpensePaidDirect(
              resolvedId,
              paidDate: payloadPaidDate,
              outletHeader: actionHeader,
            );
            await _setCachedExpensePaid(
              (
                store: localCache.getActiveStoreId(),
                scope: actionScope ?? _captureScope().scope,
              ),
              {resolvedId, rawId},
              payloadPaidDate,
            );
            break;

          case 'create_staff':
            final localId = payload['localId']?.toString();
            final serverStaff = await _createStaffDirect(
              name: payload['name']?.toString() ?? '',
              phone: payload['phone']?.toString() ?? '',
              password: payload['password']?.toString() ?? '',
              idempotencyKey: payload['idempotencyKey']?.toString(),
              outletIds: _stringList(payload['outlets']),
              defaultOutletId: payload['defaultOutletId']?.toString(),
            );
            if (localId != null && localId.isNotEmpty) {
              idMap[localId] = serverStaff.id;
              await rewriteQueuedId('employeeId', localId, serverStaff.id);
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

          case 'set_staff_active':
            final rawId = payload['employeeId']?.toString() ?? '';
            final resolvedId = idMap[rawId] ?? rawId;
            final newActive = payload['active'] == true;
            await _setStaffActiveDirect(
              employeeId: resolvedId,
              active: newActive,
            );
            final cached = localCache.getCachedStaff() ?? [];
            final idx = cached.indexWhere(
              (s) =>
                  s['id']?.toString() == resolvedId ||
                  s['id']?.toString() == rawId,
            );
            if (idx != -1) {
              cached[idx] = {...cached[idx], 'active': newActive};
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
              phone: payload['phone']?.toString() ?? '',
              active: payload['active'] as bool?,
              // Queued without `active`: read the server's current value.
              fresh: true,
              outletIds: _stringList(payload['outlets']),
              defaultOutletId: payload['defaultOutletId']?.toString(),
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

        if (!_countsAsFailure(e)) {
          // Auth, timeouts, 5xx, rate limits, unreadable replies: not this
          // action's fault. Stop the drain and try again next cycle without
          // spending its (or any other action's) retry budget.
          allSuccess = false;
          updatedQueue.add(action);
          break;
        }

        failCount++;
        final updatedAction = {
          ...action,
          'failCount': failCount,
          'lastError': e is ApiException ? e.message : e.toString(),
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
    final response = await apiClient.post(
      ApiEndpoints.changePassword,
      body: {'oldPassword': currentPassword, 'newPassword': newPassword},
    );
    // The server revokes the old session and returns a fresh token.
    if (response is Map) {
      final token = response['token']?.toString();
      if (token != null && token.isNotEmpty) {
        await secureStorage.saveToken(token);
      }
    }
  }

  Future<Product> _upsertProduct({
    required String id,
    required String name,
    required String category,
    required String unit,
    required int price,
    List<Map<String, dynamic>> slabs = const [],
    bool? active,
    int? extra,
  }) async {
    final isWeight = unit.trim().toLowerCase() == 'weight';
    final body = isWeight
        ? <String, dynamic>{
            'id': id,
            'name': name.trim(),
            'category': category.trim(),
            'active': active ?? true,
            'type': 'weight',
            'slabs': slabs,
            'extra': extra ?? 0,
          }
        : <String, dynamic>{
            'id': id,
            'name': name.trim(),
            'category': category.trim(),
            'active': active ?? true,
            'type': 'item',
            'price': price,
          };
    final response = await apiClient.post(ApiEndpoints.products, body: body);
    return Product.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Creates a new catalogue service/product
  Future<Product> createProduct({
    String? id,
    required String name,
    required String category,
    required String unit,
    required int price,
    List<Map<String, dynamic>> slabs = const [],
    bool? active,
    int? extra,
  }) async {
    final productId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : IdempotencyKeyGenerator.generate();
    return _upsertProduct(
      id: productId,
      name: name,
      category: category,
      unit: unit,
      price: price,
      slabs: slabs,
      active: active,
      extra: extra,
    );
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
    return _upsertProduct(
      id: id,
      name: name,
      category: category,
      unit: unit,
      price: price,
      slabs: slabs,
      active: active,
      extra: extra,
    );
  }
}
