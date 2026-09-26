import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/core/utils/idempotency.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';

import 'models/product_model.dart';

const _tag = 'POS_SYNC';

class PosRepository {
  final ApiClient _apiClient;
  final LocalCacheService _localCache;

  PosRepository({ApiClient? apiClient, LocalCacheService? localCache})
    : _apiClient = apiClient ?? ApiClient(),
      _localCache = localCache ?? LocalCacheService();

  /// Reads products from the local cache only — no network call.
  List<Product> getCachedProductsList() {
    try {
      final cached = _localCache.getCachedProducts();
      if (cached == null || cached.isEmpty) return [];
      return cached.map((p) => Product.fromJson(p)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches product catalogue for current active store with local cache
  Future<List<Product>> listProducts() async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      final cached = _localCache.getCachedProducts();
      if (cached != null && cached.isNotEmpty) {
        final products = cached.map((p) => Product.fromJson(p)).toList();
        final pendingCount = _localCache.getTotalPendingCount();
        SyncManager.instance.setOffline(
          pendingCount,
          'Offline · using cached catalogue',
        );
        return products;
      }
      throw Exception('No network connection and no cached products available');
    }

    try {
      SyncManager.instance.startSync('Fetching latest from cloud...');
      final response = await _apiClient.get(ApiEndpoints.products);
      if (response is List) {
        final products = response
            .map((p) => Product.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList();
        await _localCache.setCachedProducts(
          products.map((p) => p.toJson()).toList(),
        );
        SyncManager.instance.completeSync();
        return products;
      }
    } catch (e) {
      // Offline fallback: try reading cached products. But only report the
      // banner as "Offline" if we're actually offline — a bare catch here
      // used to unconditionally call setOffline() even for a genuine online
      // failure (timeout, 4xx/5xx, bad JSON), which mislabeled the banner.
      final reallyOffline = await ConnectivityService.instance.checkIsOffline();
      final cached = _localCache.getCachedProducts();
      if (cached != null && cached.isNotEmpty) {
        final products = cached.map((p) => Product.fromJson(p)).toList();
        final pendingCount = _localCache.getTotalPendingCount();
        if (reallyOffline) {
          SyncManager.instance.setOffline(
            pendingCount,
            'Offline · using cached catalogue',
          );
        } else {
          AppLogger.log(_tag, 'refresh catalogue failed', error: e);
          SyncManager.instance.setError(
            'Could not refresh catalogue — showing cached data',
          );
        }
        return products;
      }
      rethrow;
    }
    return [];
  }

  /// Fetches active store payment choices (e.g. Cash, UPI) with local fallback
  Future<List<StorePaymentMethod>> listPaymentMethods() async {
    final isOffline = await ConnectivityService.instance.checkIsOffline();
    if (isOffline) {
      final cached = _localCache.getCachedPaymentMethods();
      if (cached != null) {
        return cached
            .map(
              (m) => StorePaymentMethod.fromJson(m),
            )
            .where((m) => m.active)
            .toList();
      }
      return [];
    }

    try {
      final response = await _apiClient.get(ApiEndpoints.paymentMethodsAll);
      if (response is List) {
        final allMethods = response
            .map(
              (m) => StorePaymentMethod.fromJson(
                Map<String, dynamic>.from(m as Map),
              ),
            )
            .toList();
        await _localCache.setCachedPaymentMethods(
          allMethods.map((m) => m.toJson()).toList(),
        );
        return allMethods.where((m) => m.active).toList();
      }
    } catch (_) {
      final cached = _localCache.getCachedPaymentMethods();
      if (cached != null) {
        return cached
            .map(
              (m) => StorePaymentMethod.fromJson(m),
            )
            .where((m) => m.active)
            .toList();
      }
    }
    return [];
  }

  /// Creates a new order. Local-first: builds the order, saves it to Hive,
  /// queues the create for sync, and returns immediately — the actual POST
  /// only ever happens inside SyncEngine's batch sync (via bulk-sync), never
  /// as a separate one-off call here, so there is exactly one code path that
  /// talks to the server for order creation.
  Future<Order> createOrderOptimistic({
    required String idempotencyKey,
    required String phone,
    String customerName = '',
    required String dueDate,
    String notes = '',
    required List<Map<String, dynamic>> entries,
    Map<String, dynamic>? initialPayment,
    String? outletId,
  }) async {
    // The order's local key until the server assigns its EL- code; also
    // sent so a retry of a create whose reply was lost returns the same
    // order (docs/OFFLINE-ID-SYNC-PLAN.md §3).
    final offlineId = IdempotencyKeyGenerator.generate();
    final body = {
      'idempotencyKey': idempotencyKey,
      'offlineId': offlineId,
      'phone': phone.trim(),
      'customerName': customerName.trim(),
      'dueDate': dueDate,
      'notes': notes.trim(),
      'entries': entries,
      'initialPayment': ?initialPayment,
      'outletId': ?outletId,
    };

    final cachedProds = _localCache.getCachedProducts() ?? [];
    final prodMap = {for (var p in cachedProds) p['id']?.toString(): p};

    final orderLines = entries.map((entry) {
      final pid = entry['productId']?.toString() ?? '';
      final prod = prodMap[pid];
      final pName = prod?['name']?.toString() ?? 'Service';
      final isWeight =
          prod != null &&
          (prod['type']?.toString().toLowerCase() == 'weight' ||
              prod['unit']?.toString().toLowerCase() == 'weight' ||
              prod['unit']?.toString().toLowerCase() == 'kg');
      final pUnit =
          prod?['unit']?.toString() ?? (isWeight ? 'WEIGHT' : 'PIECE');
      final num qty = entry['quantity'] ?? 1;
      final int amount;
      if (prod != null) {
        amount = Product.fromJson(prod).computePrice(qty.toDouble());
      } else {
        final num rate = prod?['price'] ?? 0;
        amount = (qty * rate).round();
      }
      return OrderLine(
        productId: pid,
        name: pName,
        quantity: qty.toDouble(),
        unit: pUnit,
        amount: amount,
      );
    }).toList();

    final List<OrderPayment> localPayments = [];
    if (initialPayment != null) {
      localPayments.add(
        OrderPayment(
          id: 'pay_optimistic',
          amount: (initialPayment['amount'] as num?)?.toInt() ?? 0,
          date: DateTime.now().toIso8601String(),
          method: initialPayment['method']?.toString() ?? 'Cash',
        ),
      );
    }

    final localOrder = Order(
      id: '',
      offlineId: offlineId,
      name: customerName.trim(),
      phone: phone.trim(),
      date: DateTime.now().toIso8601String(),
      due: dueDate,
      status: 'Pending',
      lines: orderLines,
      payments: localPayments,
      notes: notes.trim(),
      isSynced: false,
      outletId: outletId,
    );

    // Save to local cache immediately — this is what makes the order appear
    // instantly, before anything has touched the network.
    final cachedOrders = _localCache.getCachedOrders() ?? [];
    cachedOrders.insert(0, localOrder.toJson());
    await _localCache.setCachedOrders(cachedOrders);

    await _localCache.enqueueSyncAction({
      'type': 'create_order',
      'clientActionId': IdempotencyKeyGenerator.generate(),
      'body': body,
      'offlineCode': offlineId,
      'storeId': _localCache.getActiveStoreId(),
      'outletId': outletId,
      'queuedAt': DateTime.now().toIso8601String(),
    });

    // Don't set the banner here — SyncEngine.trigger() below runs its own
    // _runSync() synchronously up to its first await, so it already reports
    // the correct state (offline vs. pending) immediately. Setting a
    // "Saved locally · syncing…" message here first, only to have trigger()
    // overwrite it with its own message in the very same tick (or shortly
    // after), was producing a visible flicker between two different banner
    // texts for the same event. SyncEngine is now the single source of
    // truth for banner state.
    //
    // Fire-and-forget: the caller (already showing the order) doesn't wait
    // on this, and SyncEngine's own mutex means it's safe to call even if a
    // sync is already running elsewhere.
    SyncEngine.instance.trigger();

    return localOrder;
  }
}
