import 'package:hive_flutter/hive_flutter.dart';

class LocalCacheService {
  static const String boxName = 'myshop_cache_box';

  /// Hive returns nested maps/lists as `Map<dynamic,dynamic>`/`List<dynamic>`,
  /// which fails explicit casts like `List<Map<String,dynamic>>.from(...)`
  /// elsewhere in the app. Recursively rebuilds with String-keyed maps.
  static dynamic deepCopy(dynamic val) {
    if (val is Map) {
      return Map<String, dynamic>.fromEntries(
        val.entries.map((e) => MapEntry(e.key.toString(), deepCopy(e.value))),
      );
    } else if (val is List) {
      return val.map(deepCopy).toList();
    }
    return val;
  }

  /// Collapses orders sharing the same non-empty `id` or the same non-empty
  /// `offlineId` down to one entry, keeping the last occurrence (most
  /// recently written). Different sync paths (bulk action reconciliation,
  /// delta pull, a concurrent write mid-sync) can each independently insert
  /// a row for the same order under some race — this is the single
  /// defensive place that guarantees the UI never shows two rows for the
  /// same order regardless of which path caused it.
  static List<Map<String, dynamic>> dedupeOrdersById(
    List<Map<String, dynamic>> orders,
  ) {
    final seenIds = <String>{};
    final seenOfflineIds = <String>{};
    final result = <Map<String, dynamic>>[];
    for (var i = orders.length - 1; i >= 0; i--) {
      final id = orders[i]['id']?.toString() ?? '';
      final offlineId = orders[i]['offlineId']?.toString() ?? '';
      if ((id.isNotEmpty && seenIds.contains(id)) ||
          (offlineId.isNotEmpty && seenOfflineIds.contains(offlineId))) {
        continue;
      }
      if (id.isNotEmpty) seenIds.add(id);
      if (offlineId.isNotEmpty) seenOfflineIds.add(offlineId);
      result.insert(0, orders[i]);
    }
    return result;
  }

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(boxName);
    await migrateLegacyOfflineIds(Hive.box(boxName));
  }

  static bool _isLegacyPlaceholder(String id) =>
      id.startsWith('LOCAL-') || id.startsWith('OFF-');

  /// One-time, idempotent move of pre-offlineId data to the two-id model:
  /// cached orders whose `id` is a `LOCAL-`/`OFF-` placeholder get
  /// `offlineId = id, id = ''`, and queued `create_order` actions (pending
  /// and dead-letter) get `body.offlineId ??= offlineCode`, so the server
  /// stores the code that queued status/payment actions still reference.
  static Future<void> migrateLegacyOfflineIds(Box box) async {
    for (final key in box.keys.toList()) {
      if (key is! String || !key.startsWith(keyCachedOrders)) continue;
      final raw = box.get(key);
      if (raw is! List) continue;
      var changed = false;
      final migrated = raw.map((e) {
        final order = deepCopy(e) as Map<String, dynamic>;
        final id = order['id']?.toString() ?? '';
        if (_isLegacyPlaceholder(id)) {
          changed = true;
          return {...order, 'offlineId': id, 'id': ''};
        }
        return order;
      }).toList();
      if (changed) await box.put(key, migrated);
    }
    for (final key in [keyPendingSyncQueue, keyDeadLetterQueue]) {
      final raw = box.get(key);
      if (raw is! List) continue;
      var changed = false;
      final migrated = raw.map((e) {
        final action = deepCopy(e) as Map<String, dynamic>;
        final body = action['body'];
        final code = action['offlineCode']?.toString() ?? '';
        if (action['type'] == 'create_order' &&
            body is Map<String, dynamic> &&
            (body['offlineId']?.toString() ?? '').isEmpty &&
            code.isNotEmpty) {
          changed = true;
          return {
            ...action,
            'body': {...body, 'offlineId': code},
          };
        }
        return action;
      }).toList();
      if (changed) await box.put(key, migrated);
    }
  }

  Box get _box => Hive.box(boxName);

  // Active Store Id
  static const String keyActiveStoreId = 'active_store_id';
  String? getActiveStoreId() => _box.get(keyActiveStoreId) as String?;
  Future<void> setActiveStoreId(String storeId) =>
      _box.put(keyActiveStoreId, storeId);
  Future<void> clearActiveStoreId() => _box.delete(keyActiveStoreId);

  // Cached User Map
  static const String keyCachedUser = 'cached_user_json';
  Map<String, dynamic>? getCachedUser() {
    final raw = _box.get(keyCachedUser);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> setCachedUser(Map<String, dynamic> userMap) =>
      _box.put(keyCachedUser, userMap);

  // Cached Current Store Details
  static const String keyCachedStoreDetails = 'cached_store_details_json';
  Map<String, dynamic>? getCachedStoreDetails() {
    final raw = _box.get(keyCachedStoreDetails);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> setCachedStoreDetails(Map<String, dynamic> storeMap) =>
      _box.put(keyCachedStoreDetails, storeMap);

  // Cached Store Profile (from GET /api/v1/profile)
  static const String keyCachedStoreProfile = 'cached_store_profile_json';
  Map<String, dynamic>? getCachedStoreProfile() {
    final raw = _box.get(keyCachedStoreProfile);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> setCachedStoreProfile(Map<String, dynamic> profileMap) =>
      _box.put(keyCachedStoreProfile, profileMap);

  // Cached Available Stores List
  static const String keyCachedAvailableStores = 'cached_available_stores_list';
  List<Map<String, dynamic>>? getCachedAvailableStores() {
    final raw = _box.get(keyCachedAvailableStores);
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return null;
  }

  Future<void> setCachedAvailableStores(
    List<Map<String, dynamic>> storesList,
  ) => _box.put(keyCachedAvailableStores, storesList);

  // Cached Dashboard Metrics — outlet-scoped once _outletScopedKey is
  // defined below; declared here to keep it grouped with the other cached
  // reads, same as before.
  static const String keyCachedDashboardMetrics =
      'cached_dashboard_metrics_json';
  Map<String, dynamic>? getCachedDashboardMetrics() =>
      getCachedDashboardMetricsForScope(null);

  Future<void> setCachedDashboardMetrics(Map<String, dynamic> metrics) =>
      setCachedDashboardMetricsForScope(null, metrics);

  Map<String, dynamic>? getCachedDashboardMetricsForScope(String? scope) {
    final raw = _box.get(_outletScopedKey(keyCachedDashboardMetrics, scope));
    if (raw is Map) {
      return deepCopy(raw) as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> setCachedDashboardMetricsForScope(
    String? scope,
    Map<String, dynamic> metrics,
  ) => _box.put(_outletScopedKey(keyCachedDashboardMetrics, scope), metrics);

  // Cached Expenses List
  static const String keyCachedExpenses = 'cached_expenses_list';
  List<Map<String, dynamic>>? getCachedExpenses() =>
      getCachedExpensesForScope(null);

  Future<void> setCachedExpenses(List<Map<String, dynamic>> expensesList) =>
      setCachedExpensesForScope(null, expensesList);

  List<Map<String, dynamic>>? getCachedExpensesForScope(String? scope) {
    final raw = _box.get(_outletScopedKey(keyCachedExpenses, scope));
    if (raw is List) {
      return raw.map((e) => deepCopy(e) as Map<String, dynamic>).toList();
    }
    return null;
  }

  Future<void> setCachedExpensesForScope(
    String? scope,
    List<Map<String, dynamic>> expensesList,
  ) => _box.put(_outletScopedKey(keyCachedExpenses, scope), expensesList);

  // Cached Staff List
  static const String keyCachedStaff = 'cached_staff_list';
  List<Map<String, dynamic>>? getCachedStaff() {
    final raw = _box.get(keyCachedStaff);
    if (raw is List) {
      return raw.map((e) => deepCopy(e) as Map<String, dynamic>).toList();
    }
    return null;
  }

  Future<void> setCachedStaff(List<Map<String, dynamic>> staffList) =>
      _box.put(keyCachedStaff, staffList);

  // Cached Payment Methods List
  static const String keyCachedPaymentMethods = 'cached_payment_methods_list';
  List<Map<String, dynamic>>? getCachedPaymentMethods() {
    final raw = _box.get(keyCachedPaymentMethods);
    if (raw is List) {
      return raw.map((e) => deepCopy(e) as Map<String, dynamic>).toList();
    }
    return null;
  }

  Future<void> setCachedPaymentMethods(
    List<Map<String, dynamic>> methodsList,
  ) => _box.put(keyCachedPaymentMethods, methodsList);

  // Cached Products List
  static const String keyCachedProducts = 'cached_products_list';
  List<Map<String, dynamic>>? getCachedProducts() {
    final raw = _box.get(keyCachedProducts);
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return null;
  }

  Future<void> setCachedProducts(List<Map<String, dynamic>> productsList) =>
      _box.put(keyCachedProducts, productsList);

  // Cached Orders List — scoped per store, so switching the logged-in store
  // (or a second employee logging into a different store on the same
  // device) never shows the previous store's cached orders.
  static const String keyCachedOrders = 'cached_orders_list';
  String _storeScopedKey(String baseKey) =>
      '$baseKey::${getActiveStoreId() ?? 'none'}';

  // Outlet scope (multi-outlet rollout) — per store, mirrors keyActiveStoreId.
  static const String keyAllowedOutlets = 'allowed_outlets';
  static const String keyActiveOutletId = 'active_outlet_id';
  static const String keyAllOutletsScope = 'all_outlets_scope';

  List<Map<String, dynamic>>? getAllowedOutlets() {
    final raw = _box.get(_storeScopedKey(keyAllowedOutlets));
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return null;
  }

  /// Writes allowed outlets for an arbitrary (not necessarily active) store —
  /// login caches every organization's outlets at once, the same way
  /// [setCachedAvailableStores] already caches every store's summary.
  Future<void> setAllowedOutletsForStore(
    String storeId,
    List<Map<String, dynamic>> outlets,
  ) => _box.put('$keyAllowedOutlets::$storeId', outlets);

  String? getActiveOutletId() =>
      _box.get(_storeScopedKey(keyActiveOutletId)) as String?;
  Future<void> setActiveOutletId(String outletId) =>
      _box.put(_storeScopedKey(keyActiveOutletId), outletId);
  Future<void> clearActiveOutletId() =>
      _box.delete(_storeScopedKey(keyActiveOutletId));

  bool isAllOutletsScope() =>
      _box.get(_storeScopedKey(keyAllOutletsScope)) as bool? ?? false;
  Future<void> setAllOutletsScope(bool value) =>
      _box.put(_storeScopedKey(keyAllOutletsScope), value);
  Future<void> clearAllOutletsScope() =>
      _box.delete(_storeScopedKey(keyAllOutletsScope));

  // Outlet-scoped key: switching the active outlet (or All-outlets scope)
  // must not serve the previous scope's cached orders or resume its sync
  // cursor — see keyCachedOrders/keyLastSyncCursor/keyCachedDashboardMetrics.
  //
  // [scope] names a scope explicitly — an outlet id, or [allScope] for the
  // combined view — so a sync can fill an outlet other than the active one
  // without switching to it; null means the active scope.
  static const String allScope = 'all';

  String _outletScopedKey(String baseKey, [String? scope]) =>
      '$baseKey::${getActiveStoreId() ?? 'none'}'
      '::${scope ?? getActiveOutletId() ?? (isAllOutletsScope() ? 'all' : 'none')}';

  /// Drops one scope's cached orders, delta cursor, dashboard and expenses.
  /// Pending/dead-letter queues, other scopes and organization-wide data are
  /// left alone: queued actions carry their own outlet and must still flush.
  Future<void> clearScopeData(String scope) async {
    for (final base in [
      keyCachedOrders,
      keyLastSyncCursor,
      keyCachedDashboardMetrics,
      keyCachedExpenses,
    ]) {
      await _box.delete(_outletScopedKey(base, scope));
    }
  }

  List<Map<String, dynamic>>? getCachedOrders() =>
      getCachedOrdersForScope(null);

  Future<void> setCachedOrders(List<Map<String, dynamic>> ordersList) =>
      setCachedOrdersForScope(null, ordersList);

  List<Map<String, dynamic>>? getCachedOrdersForScope(String? scope) {
    final raw = _box.get(_outletScopedKey(keyCachedOrders, scope));
    if (raw is List) {
      return raw.map((e) => deepCopy(e) as Map<String, dynamic>).toList();
    }
    return null;
  }

  Future<void> setCachedOrdersForScope(
    String? scope,
    List<Map<String, dynamic>> ordersList,
  ) => _box.put(_outletScopedKey(keyCachedOrders, scope), ordersList);

  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) {
    final key =
        '$keyCachedOrders::${getActiveStoreId() ?? 'none'}'
        '::${allOutlets ? 'all' : (outletId ?? 'none')}';
    return _box.get(key) is List;
  }

  /// The server code (`EL-…`) of a cached order carrying [offlineId], looked
  /// up across every outlet scope's cached orders; null while unsynced or
  /// unknown. Queued actions keep the offline id they were written with, so
  /// the queue push uses this to send the server code once it is known.
  String? findSyncedIdByOfflineId(String offlineId) {
    if (offlineId.isEmpty) return null;
    for (final key in _box.keys) {
      if (key is! String || !key.startsWith(keyCachedOrders)) continue;
      final raw = _box.get(key);
      if (raw is! List) continue;
      for (final order in raw) {
        if (order is Map && order['offlineId'] == offlineId) {
          final id = order['id']?.toString() ?? '';
          if (id.isNotEmpty) return id;
        }
      }
    }
    return null;
  }

  // Delta-sync cursor (opaque server-issued string) — also per outlet scope,
  // so resuming sync after switching scope doesn't skip the new scope's
  // changes or replay the old scope's cursor.
  static const String keyLastSyncCursor = 'last_sync_cursor';
  String? getLastSyncCursor() => getLastSyncCursorForScope(null);
  Future<void> setLastSyncCursor(String cursor) =>
      setLastSyncCursorForScope(null, cursor);

  String? getLastSyncCursorForScope(String? scope) =>
      _box.get(_outletScopedKey(keyLastSyncCursor, scope)) as String?;
  Future<void> setLastSyncCursorForScope(String? scope, String cursor) =>
      _box.put(_outletScopedKey(keyLastSyncCursor, scope), cursor);

  // Cached In-Progress Cart
  static const String keyCachedCart = 'cached_cart_json';
  Map<String, dynamic>? getCachedCart() {
    final raw = _box.get(keyCachedCart);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> setCachedCart(Map<String, dynamic> cartMap) =>
      _box.put(keyCachedCart, cartMap);
  Future<void> clearCachedCart() => _box.delete(keyCachedCart);

  // Offline Pending Sync Queue
  static const String keyPendingSyncQueue = 'pending_sync_queue_list';
  List<Map<String, dynamic>> getPendingSyncQueue() {
    final raw = _box.get(keyPendingSyncQueue);
    if (raw is List) {
      return raw.map((e) => deepCopy(e) as Map<String, dynamic>).toList();
    }
    return [];
  }

  Future<void> enqueueSyncAction(Map<String, dynamic> action) async {
    final current = getPendingSyncQueue();
    current.add(action);
    await _box.put(keyPendingSyncQueue, current);
  }

  Future<void> setPendingSyncQueue(List<Map<String, dynamic>> queue) =>
      _box.put(keyPendingSyncQueue, queue);
  Future<void> clearPendingSyncQueue() => _box.delete(keyPendingSyncQueue);

  // Actions that failed enough times in a row to stop being retried
  // silently on every sync cycle — parked here instead of the main queue so
  // one permanently-broken action can't keep the sync banner stuck on
  // "paused" forever. A manual "Sync now"/"Retry" tap moves them back into
  // the pending queue for one fresh attempt.
  static const String keyDeadLetterQueue = 'dead_letter_queue_list';
  List<Map<String, dynamic>> getDeadLetterQueue() {
    final raw = _box.get(keyDeadLetterQueue);
    if (raw is List) {
      return raw.map((e) => deepCopy(e) as Map<String, dynamic>).toList();
    }
    return [];
  }

  Future<void> setDeadLetterQueue(List<Map<String, dynamic>> queue) =>
      _box.put(keyDeadLetterQueue, queue);

  // Offline Pending Owner Actions Queue (Owner-only writes)
  static const String keyPendingOwnerActionsQueue =
      'pending_owner_actions_queue_list';
  List<Map<String, dynamic>> getPendingOwnerActionsQueue() {
    final raw = _box.get(keyPendingOwnerActionsQueue);
    if (raw is List) {
      return raw.map((e) => deepCopy(e) as Map<String, dynamic>).toList();
    }
    return [];
  }

  Future<void> enqueueOwnerAction(Map<String, dynamic> action) async {
    final current = getPendingOwnerActionsQueue();
    current.add(action);
    await _box.put(keyPendingOwnerActionsQueue, current);
  }

  Future<void> setPendingOwnerActionsQueue(List<Map<String, dynamic>> queue) =>
      _box.put(keyPendingOwnerActionsQueue, queue);
  Future<void> clearPendingOwnerActionsQueue() =>
      _box.delete(keyPendingOwnerActionsQueue);

  // Dead letter queue for permanently failing owner actions
  static const String keyDeadLetterOwnerActionsQueue =
      'dead_letter_owner_actions_queue_list';
  List<Map<String, dynamic>> getDeadLetterOwnerActionsQueue() {
    final raw = _box.get(keyDeadLetterOwnerActionsQueue);
    if (raw is List) {
      return raw.map((e) => deepCopy(e) as Map<String, dynamic>).toList();
    }
    return [];
  }

  Future<void> setDeadLetterOwnerActionsQueue(
    List<Map<String, dynamic>> queue,
  ) => _box.put(keyDeadLetterOwnerActionsQueue, queue);

  /// Combined count of orders pending sync and owner actions pending sync.
  int getTotalPendingCount() {
    return getPendingSyncQueue().length + getPendingOwnerActionsQueue().length;
  }

  /// Orders + owner actions parked after exhausting their retries. They are
  /// excluded from [getTotalPendingCount] (so they stop being retried on every
  /// cycle) but are still unsynced data the user must be told about.
  int getTotalDeadLetterCount() {
    return getDeadLetterQueue().length +
        getDeadLetterOwnerActionsQueue().length;
  }

  // Generic key-value helpers for offline storage
  dynamic get(String key) => _box.get(key);
  Future<void> put(String key, dynamic value) => _box.put(key, value);
  Future<void> delete(String key) => _box.delete(key);

  // Outlet an employee picked, per user + organization. Kept across
  // logout (see [clear]) so the next sign-in skips the outlet picker.
  static const String keyRememberedOutlet = 'remembered_outlet';
  String? getRememberedOutlet(String userId, String storeId) =>
      _box.get('$keyRememberedOutlet::$userId::$storeId') as String?;
  Future<void> setRememberedOutlet(
    String userId,
    String storeId,
    String outletId,
  ) => _box.put('$keyRememberedOutlet::$userId::$storeId', outletId);

  /// Clears cache on logout, except remembered outlet choices.
  Future<void> clear() async {
    await _box.deleteAll(
      _box.keys.where(
        (k) => !(k is String && k.startsWith(keyRememberedOutlet)),
      ),
    );
  }
}
