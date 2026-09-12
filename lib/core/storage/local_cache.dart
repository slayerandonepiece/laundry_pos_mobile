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

  /// Collapses orders sharing the same `id` down to one entry, keeping the
  /// last occurrence (most recently written). Different sync paths (bulk
  /// action reconciliation, delta pull, a concurrent write mid-sync) can
  /// each independently insert a row for the same order under some race —
  /// this is the single defensive place that guarantees the UI never shows
  /// two rows for the same order regardless of which path caused it.
  static List<Map<String, dynamic>> dedupeOrdersById(
    List<Map<String, dynamic>> orders,
  ) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (var i = orders.length - 1; i >= 0; i--) {
      final id = orders[i]['id']?.toString();
      if (id == null || id.isEmpty || seen.add(id)) {
        result.insert(0, orders[i]);
      }
    }
    return result;
  }

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(boxName);
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

  List<Map<String, dynamic>>? getCachedOrders() {
    final raw = _box.get(_storeScopedKey(keyCachedOrders));
    if (raw is List) {
      return raw.map((e) => deepCopy(e) as Map<String, dynamic>).toList();
    }
    return null;
  }

  Future<void> setCachedOrders(List<Map<String, dynamic>> ordersList) =>
      _box.put(_storeScopedKey(keyCachedOrders), ordersList);

  // Delta-sync cursor (opaque server-issued string) — also per store, so
  // resuming sync after switching stores doesn't skip that store's changes.
  static const String keyLastSyncCursor = 'last_sync_cursor';
  String? getLastSyncCursor() =>
      _box.get(_storeScopedKey(keyLastSyncCursor)) as String?;
  Future<void> setLastSyncCursor(String cursor) =>
      _box.put(_storeScopedKey(keyLastSyncCursor), cursor);

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

  // Generic key-value helpers for offline storage
  dynamic get(String key) => _box.get(key);
  Future<void> put(String key, dynamic value) => _box.put(key, value);
  Future<void> delete(String key) => _box.delete(key);

  /// Clears cache on logout
  Future<void> clear() async {
    await _box.clear();
  }
}
