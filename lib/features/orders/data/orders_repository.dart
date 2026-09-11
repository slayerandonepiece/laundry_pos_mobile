import 'dart:typed_data';

import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/core/utils/idempotency.dart';

import 'models/order_model.dart';

class OrdersRepository {
  final ApiClient _apiClient;
  final LocalCacheService _localCache;

  OrdersRepository({ApiClient? apiClient, LocalCacheService? localCache})
    : _apiClient = apiClient ?? ApiClient(),
      _localCache = localCache ?? LocalCacheService();

  /// Reads orders from the local cache only — no network call. This is the
  /// only thing the Orders screen calls on a normal open; a network sync
  /// only happens via [SyncEngine], triggered by pull-to-refresh, a
  /// reconnect, or a manual "Sync now" tap.
  List<Order> getCachedOrdersList() {
    final cached = _localCache.getCachedOrders();
    if (cached == null) return [];
    final orders = LocalCacheService.dedupeOrdersById(cached)
        .map((o) => Order.fromJson(o))
        .toList();
    // Delta sync upserts by id in whatever order the server returned them
    // (oldest-changed first), which is not display order — always sort
    // newest-first here rather than relying on cache insertion order.
    // Orders still on a LOCAL-xxx/OFF-xxx placeholder code (not yet synced)
    // have no order number yet, so they sort to the very top.
    orders.sort((a, b) => _orderSortKey(b).compareTo(_orderSortKey(a)));
    return orders;
  }

  static int _orderSortKey(Order order) {
    final match = RegExp(r'^EL-(\d+)$').firstMatch(order.id);
    if (match != null) return int.parse(match.group(1)!);
    return 1 << 30; // unsynced placeholder — treat as newest
  }

  /// Looks up a returning customer's name from a prior order with the same
  /// phone number, purely from the local cache (works offline, no network
  /// round trip). Returns the most recently placed matching order's name, or
  /// null if there's no cached order for this phone or none of them have a
  /// name on file.
  String? findCustomerNameByPhone(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return null;
    for (final order in getCachedOrdersList()) {
      final orderDigits = order.phone.replaceAll(RegExp(r'\D'), '');
      if (orderDigits.endsWith(digitsOnly) && order.name.trim().isNotEmpty) {
        return order.name.trim();
      }
    }
    return null;
  }

  /// Returning-customer lookup for the new-order flow's phone step: checks
  /// the local cache first (instant, works offline), and only if nothing is
  /// cached for this phone does it ask the server (which can see orders
  /// placed on other devices too). If the server call fails for any reason
  /// — no connectivity included — this just returns null rather than
  /// throwing, so the flow can still proceed with a fresh/blank name; a
  /// failed lookup is never a reason to block creating the order.
  Future<String?> lookupCustomerName(String phone) async {
    final local = findCustomerNameByPhone(phone);
    if (local != null) return local;

    try {
      final response = await _apiClient.get(ApiEndpoints.customerLookup(phone));
      if (response is Map) {
        final name = response['name'];
        if (name is String && name.trim().isNotEmpty) return name.trim();
      }
    } catch (_) {
      // Offline or request failed — no match to report, caller proceeds anyway.
    }
    return null;
  }

  /// Fetches recent orders for active store from server and updates local cache
  Future<List<Order>> fetchRecentOrders({
    int limit = 30,
    String sort = 'recent',
  }) async {
    try {
      final response = await _apiClient.get(
        '${ApiEndpoints.orders}?limit=$limit&sort=$sort',
      );
      if (response is List) {
        final orders = response
            .map((o) => Order.fromJson(Map<String, dynamic>.from(o as Map)))
            .toList();
        await _localCache.setCachedOrders(
          orders.map((o) => o.toJson()).toList(),
        );
        return orders;
      }
      throw Exception('Failed to load recent orders: invalid response');
    } catch (_) {
      final cached = _localCache.getCachedOrders();
      if (cached != null && cached.isNotEmpty) {
        return cached.map((o) => Order.fromJson(o)).toList();
      }
      rethrow;
    }
  }

  /// Fetches single order details including invoice state
  Future<Order> getOrderDetail(String orderCode) async {
    try {
      final response = await _apiClient.get(
        ApiEndpoints.orderDetail(orderCode),
      );
      if (response is Map) {
        final order = Order.fromJson(Map<String, dynamic>.from(response));
        await _updateCachedOrder(order);
        return order;
      }
      throw Exception('Failed to load order details');
    } catch (_) {
      final cached = _localCache.getCachedOrders();
      if (cached != null) {
        final match = cached.firstWhere(
          (c) => c['id'] == orderCode || c['orderCode'] == orderCode,
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          return Order.fromJson(match);
        }
      }
      rethrow;
    }
  }

  /// Updates work status (Pending / In Progress / Ready / Delivered).
  /// Local-first: writes the change to cache and queues it for sync, then
  /// returns immediately — never waits on the network. Callers are expected
  /// to trigger SyncEngine themselves afterward (kept out of this repository
  /// to avoid a circular import between OrdersRepository and SyncEngine).
  Future<Order> updateStatus(String orderCode, String status) async {
    final updatedJson = await _applyLocalUpdate(
      orderCode,
      (json) => json..['status'] = status,
    );

    await _localCache.enqueueSyncAction({
      'type': 'update_status',
      'clientActionId': IdempotencyKeyGenerator.generate(),
      'orderCode': orderCode,
      'status': status,
      'storeId': _localCache.getActiveStoreId(),
      'queuedAt': DateTime.now().toIso8601String(),
    });

    final pendingCount = _localCache.getPendingSyncQueue().length;
    SyncManager.instance.setOffline(pendingCount, 'Saved locally · syncing…');

    return Order.fromJson(updatedJson);
  }

  /// Records payment for outstanding balance (Cash or UPI). Local-first —
  /// see [updateStatus] for the same reasoning.
  Future<Order> recordPayment(
    String orderCode,
    int amount,
    String method,
  ) async {
    final updatedJson = await _applyLocalUpdate(orderCode, (json) {
      final payments = List<Map<String, dynamic>>.from(json['payments'] ?? []);
      payments.add({
        'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
        'amount': amount,
        'method': method,
        'date': DateTime.now().toIso8601String(),
      });
      json['payments'] = payments;
      return json;
    });

    await _localCache.enqueueSyncAction({
      'type': 'record_payment',
      'clientActionId': IdempotencyKeyGenerator.generate(),
      'orderCode': orderCode,
      'amount': amount,
      'method': method,
      'storeId': _localCache.getActiveStoreId(),
      'queuedAt': DateTime.now().toIso8601String(),
    });

    final pendingCount = _localCache.getPendingSyncQueue().length;
    SyncManager.instance.setOffline(pendingCount, 'Saved locally · syncing…');

    return Order.fromJson(updatedJson);
  }

  /// Applies [mutate] to the cached order matching [orderCode] and persists
  /// it. Shared by updateStatus/recordPayment so both write through the same
  /// find-mutate-save path.
  Future<Map<String, dynamic>> _applyLocalUpdate(
    String orderCode,
    Map<String, dynamic> Function(Map<String, dynamic> json) mutate,
  ) async {
    final cached = _localCache.getCachedOrders() ?? [];
    final index = cached.indexWhere(
      (c) => c['id'] == orderCode || c['orderCode'] == orderCode,
    );
    if (index == -1) {
      throw Exception('Order not found locally.');
    }
    final updatedJson = mutate(Map<String, dynamic>.from(cached[index]));
    cached[index] = updatedJson;
    await _localCache.setCachedOrders(cached);
    return updatedJson;
  }

  /// Gets or creates customer order invoice. This genuinely needs the
  /// server (invoice numbers are server-assigned) — no offline fallback is
  /// possible, so callers that already succeeded locally (payment/status)
  /// must catch a failure here separately rather than treat it as fatal.
  Future<InvoiceInfo> getOrCreateInvoice(String orderCode) async {
    final response = await _apiClient.get(ApiEndpoints.orderInvoice(orderCode));
    if (response is Map) {
      return InvoiceInfo.fromJson(Map<String, dynamic>.from(response));
    }
    throw Exception('Failed to generate invoice');
  }

  /// Fetches raw invoice PDF bytes
  Future<Uint8List> getInvoicePdfBytes(String orderCode) async {
    final res = await _apiClient.getRaw(
      ApiEndpoints.orderInvoicePdf(orderCode),
    );
    if (res.statusCode == 200) {
      return res.bodyBytes;
    }
    throw Exception('Failed to download invoice PDF');
  }

  /// Processes the pending offline queue in one batched request, in the
  /// order the actions were queued. Only actions belonging to the currently
  /// active store are sent — an action queued under a different store (e.g.
  /// this device was later used to log into another store before it synced)
  /// stays queued untouched until that store is active again, so it can
  /// never be replayed under the wrong store's header.
  ///
  /// Returns true if the request reached the server at all (regardless of
  /// individual action outcomes), false if the whole request failed (e.g.
  /// no connectivity) — SyncEngine uses this to drive its failure-streak
  /// backoff. An action is only ever removed from the queue once the server
  /// has confirmed it 'success'; 'skipped' and 'failed' actions are kept
  /// queued for the next attempt — offline data is never discarded just
  /// because a sync attempt didn't fully succeed.
  Future<bool> processPendingSyncQueue() async {
    final queue = _localCache.getPendingSyncQueue();
    if (queue.isEmpty) return true;

    final currentStoreId = _localCache.getActiveStoreId();
    final dueNow = <Map<String, dynamic>>[];
    final otherStore = <Map<String, dynamic>>[];
    for (final action in queue) {
      final actionStoreId = action['storeId'] as String?;
      if (actionStoreId == null || actionStoreId == currentStoreId) {
        dueNow.add(action);
      } else {
        otherStore.add(action);
      }
    }

    // Drop any update_status/record_payment action that can never resolve
    // because its parent order was never actually created — it targets a
    // LOCAL-xxx/OFF-xxx placeholder with no matching create_order action
    // anywhere in the queue (e.g. an earlier bug lost that create action
    // but left this dependent one behind). The server will keep saying
    // "not created yet" identically forever, so this must be pruned rather
    // than retried indefinitely — the underlying order stays visible in
    // the cache exactly as it is, just permanently unsynced; nothing about
    // the order itself is deleted, only this dead action.
    final createOfflineCodes = queue
        .where((a) => a['type'] == 'create_order')
        .map((a) => a['offlineCode']?.toString())
        .whereType<String>()
        .toSet();
    final orphaned = dueNow.where((a) {
      if (a['type'] == 'create_order') return false;
      final ref = a['orderCode']?.toString() ?? '';
      final isPlaceholder = ref.startsWith('LOCAL-') || ref.startsWith('OFF-');
      return isPlaceholder && !createOfflineCodes.contains(ref);
    }).toList();
    if (orphaned.isNotEmpty) {
      dueNow.removeWhere(orphaned.contains);
      await _localCache.setPendingSyncQueue([...dueNow, ...otherStore]);
    }

    if (dueNow.isEmpty) {
      // Nothing to push for this store right now (everything queued belongs
      // to a different store, or was just pruned as unresolvable). Leave
      // SyncManager state to SyncEngine, which decides the final banner
      // state once it knows the overall queue size.
      return true;
    }

    // Backfill clientActionId for any action queued before this field
    // existed, so the bulk-sync response can always be matched back.
    var backfilled = false;
    for (final action in dueNow) {
      if ((action['clientActionId']?.toString() ?? '').isEmpty) {
        action['clientActionId'] = IdempotencyKeyGenerator.generate();
        backfilled = true;
      }
    }
    if (backfilled) {
      await _localCache.setPendingSyncQueue([...dueNow, ...otherStore]);
    }

    SyncManager.instance.startSync(
      'Syncing ${dueNow.length} offline changes...',
    );

    final actions = dueNow.map(_toBulkSyncAction).toList();

    try {
      final response = await _apiClient.post(
        ApiEndpoints.ordersBulkSync,
        body: {'actions': actions},
      );

      final rawResults = (response is Map ? response['results'] : null);
      final resultsById = <String, Map<String, dynamic>>{
        for (final r in (rawResults is List ? rawResults : <dynamic>[]))
          if (r is Map && r['clientActionId'] != null)
            r['clientActionId'].toString(): Map<String, dynamic>.from(r),
      };

      final cached = _localCache.getCachedOrders() ?? [];
      final completedIds = <String>{};
      final lastErrorById = <String, String>{};

      for (final action in dueNow) {
        final clientActionId = action['clientActionId']?.toString();
        final result = clientActionId != null
            ? resultsById[clientActionId]
            : null;

        if (result == null || result['status'] != 'success') {
          if (result != null &&
              result['error'] != null &&
              clientActionId != null) {
            lastErrorById[clientActionId] = result['error'].toString();
          }
          continue;
        }
        if (clientActionId != null) completedIds.add(clientActionId);

        final orderJson = result['order'];
        if (orderJson is Map) {
          final confirmedOrder = Order.fromJson(
            Map<String, dynamic>.from(orderJson),
          );
          final placeholderCode = action['type'] == 'create_order'
              ? (action['offlineCode'] as String? ?? '')
              : (action['orderCode'] as String? ?? '');
          final idx = cached.indexWhere(
            (c) =>
                c['id'] == placeholderCode || c['orderCode'] == placeholderCode,
          );
          if (idx != -1) {
            cached[idx] = confirmedOrder.toJson();
          } else {
            cached.insert(0, confirmedOrder.toJson());
          }
        }
      }

      await _localCache.setCachedOrders(
        LocalCacheService.dedupeOrdersById(cached),
      );

      // Re-read the queue rather than writing back the `dueNow`/`otherStore`
      // snapshot taken at the top of this call — another action (e.g. a
      // second order created while this request was in flight) can have
      // been enqueued in the meantime, and blindly overwriting with the
      // stale snapshot would silently discard it.
      final currentQueue = _localCache.getPendingSyncQueue();
      final remaining = currentQueue
          .map((a) {
            final id = a['clientActionId']?.toString();
            if (id != null && lastErrorById.containsKey(id)) {
              return {...a, 'lastError': lastErrorById[id]};
            }
            return a;
          })
          .where((a) {
            final id = a['clientActionId']?.toString();
            return id == null || !completedIds.contains(id);
          })
          .toList();
      await _localCache.setPendingSyncQueue(remaining);

      return true;
    } catch (_) {
      // Whole request failed (still offline, server unreachable, etc.) —
      // leave the queue exactly as it was; nothing synced, nothing lost.
      SyncManager.instance.setOffline(queue.length);
      return false;
    }
  }

  /// Pulls remote changes since the last successful sync, in pages, and
  /// upserts them into the local cache by id (replace if the id already
  /// exists, insert if new) — this is how orders another employee created
  /// or updated on the same store show up here without re-downloading the
  /// whole order list every time. A row the server marks `deleted` (a
  /// cancelled order) is removed locally rather than upserted.
  ///
  /// Returns true if it reached the server (even with zero new rows), false
  /// on a network failure.
  Future<bool> syncOrdersDelta({int maxBatches = 10, int limit = 50}) async {
    try {
      for (var i = 0; i < maxBatches; i++) {
        final cursor = _localCache.getLastSyncCursor();
        final query = cursor == null
            ? 'limit=$limit'
            : 'since=${Uri.encodeComponent(cursor)}&limit=$limit';
        final response = await _apiClient.get(
          '${ApiEndpoints.ordersSync}?$query',
        );
        if (response is! Map) break;

        final rawOrders = response['orders'];
        if (rawOrders is List && rawOrders.isNotEmpty) {
          final cached = _localCache.getCachedOrders() ?? [];
          // A create_order action can reach the server successfully while
          // the client never gets to see the response (dropped connection
          // right after the server committed) — the local placeholder then
          // never gets reconciled by processPendingSyncQueue, and this
          // order still has a create_order action sitting in the queue.
          // If delta pull then blindly inserted it under its real id, the
          // placeholder and the real order would both show up as separate
          // rows. While any create is still queued, skip adding order rows
          // that don't already match something in cache — the queued
          // create will reconcile correctly (same idempotencyKey returns
          // the same order) on the very next successful push.
          final hasPendingCreates = _localCache.getPendingSyncQueue().any(
            (a) => a['type'] == 'create_order',
          );
          for (final raw in rawOrders) {
            final json = Map<String, dynamic>.from(raw as Map);
            final deleted = json['deleted'] == true;
            final idx = cached.indexWhere((c) => c['id'] == json['id']);
            if (deleted) {
              if (idx != -1) cached.removeAt(idx);
              continue;
            }
            if (idx != -1) {
              cached[idx] = json;
            } else if (!hasPendingCreates) {
              cached.add(json);
            }
          }
          await _localCache.setCachedOrders(
            LocalCacheService.dedupeOrdersById(cached),
          );
        }

        final nextCursor = response['nextCursor'];
        if (nextCursor is String) {
          await _localCache.setLastSyncCursor(nextCursor);
        }
        if (nextCursor == null) break; // caught up
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Maps a locally-queued action to the bulk-sync API's action shape.
  Map<String, dynamic> _toBulkSyncAction(Map<String, dynamic> action) {
    final clientActionId = action['clientActionId']?.toString() ?? '';
    final type = action['type'];
    if (type == 'create_order') {
      return {
        'type': 'create_order',
        'clientActionId': clientActionId,
        'offlineCode': action['offlineCode'],
        'payload': LocalCacheService.deepCopy(action['body']),
      };
    } else if (type == 'update_status') {
      return {
        'type': 'update_status',
        'clientActionId': clientActionId,
        'orderRef': action['orderCode'],
        'status': action['status'],
      };
    }
    // record_payment
    return {
      'type': 'record_payment',
      'clientActionId': clientActionId,
      'orderRef': action['orderCode'],
      'amount': action['amount'],
      'method': action['method'],
    };
  }

  Future<void> _updateCachedOrder(Order updated) async {
    final cached = _localCache.getCachedOrders();
    if (cached == null) return;
    final index = cached.indexWhere(
      (c) => c['id'] == updated.id || c['orderCode'] == updated.id,
    );
    if (index != -1) {
      cached[index] = updated.toJson();
    } else {
      cached.insert(0, updated.toJson());
    }
    await _localCache.setCachedOrders(cached);
  }
}
