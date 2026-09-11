import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/core/utils/idempotency.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';

import 'models/product_model.dart';

class PosRepository {
  final ApiClient _apiClient;
  final LocalCacheService _localCache;

  PosRepository({ApiClient? apiClient, LocalCacheService? localCache})
    : _apiClient = apiClient ?? ApiClient(),
      _localCache = localCache ?? LocalCacheService();

  /// Reads products from the local cache only — no network call.
  List<Product> getCachedProductsList() {
    final cached = _localCache.getCachedProducts();
    if (cached == null || cached.isEmpty) return [];
    return cached.map((p) => Product.fromJson(p)).toList();
  }

  /// Fetches product catalogue for current active store with local cache
  Future<List<Product>> listProducts() async {
    try {
      SyncManager.instance.startSync('Syncing products...');
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
    } catch (_) {
      // Offline fallback: try reading cached products
      final cached = _localCache.getCachedProducts();
      if (cached != null && cached.isNotEmpty) {
        final products = cached.map((p) => Product.fromJson(p)).toList();
        final pendingCount = _localCache.getPendingSyncQueue().length;
        SyncManager.instance.setOffline(
          pendingCount,
          'Offline · using cached catalogue',
        );
        return products;
      }
      rethrow;
    }
    return [];
  }

  /// Fetches active store payment choices (e.g. Cash, UPI) with local fallback
  Future<List<StorePaymentMethod>> listPaymentMethods() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.paymentMethods);
      if (response is List) {
        final methods = response
            .map(
              (m) => StorePaymentMethod.fromJson(
                Map<String, dynamic>.from(m as Map),
              ),
            )
            .where((m) => m.active)
            .toList();
        await _localCache.put(
          'cached_payment_methods',
          methods.map((m) => m.toJson()).toList(),
        );
        return methods;
      }
    } catch (_) {
      final raw = _localCache.get('cached_payment_methods');
      if (raw is List) {
        return raw
            .map(
              (m) => StorePaymentMethod.fromJson(
                Map<String, dynamic>.from(m as Map),
              ),
            )
            .toList();
      }
    }
    return [
      StorePaymentMethod(id: 'pm_cash', name: 'Cash', active: true),
      StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
    ];
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
  }) async {
    final body = {
      'idempotencyKey': idempotencyKey,
      'phone': phone.trim(),
      'customerName': customerName.trim(),
      'dueDate': dueDate,
      'notes': notes.trim(),
      'entries': entries,
      'initialPayment': ?initialPayment,
    };

    final offlineCode =
        'LOCAL-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
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
      id: offlineCode,
      name: customerName.trim(),
      phone: phone.trim(),
      date: DateTime.now().toIso8601String(),
      due: dueDate,
      status: 'Pending',
      lines: orderLines,
      payments: localPayments,
      notes: notes.trim(),
      isSynced: false,
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
      'offlineCode': offlineCode,
      'storeId': _localCache.getActiveStoreId(),
      'queuedAt': DateTime.now().toIso8601String(),
    });

    final pendingCount = _localCache.getPendingSyncQueue().length;
    SyncManager.instance.setOffline(pendingCount, 'Saved locally · syncing…');

    // Fire-and-forget: the caller (already showing the order) doesn't wait
    // on this, and SyncEngine's own mutex means it's safe to call even if a
    // sync is already running elsewhere.
    SyncEngine.instance.trigger();

    return localOrder;
  }
}
