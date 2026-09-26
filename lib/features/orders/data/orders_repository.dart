import 'dart:typed_data';

import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/core/utils/idempotency.dart';

import 'models/order_model.dart';

const _tag = 'ORDERS_SYNC';

class OrdersRepository {
  final ApiClient _apiClient;
  final LocalCacheService _localCache;

  // A queue with many offline actions can take the server longer than the
  // client's 30s request timeout (see ApiClient._requestTimeout) to process
  // in one call. Sending small, sequential batches instead keeps each
  // request comfortably under that timeout.
  static const int _bulkSyncBatchSize = 5;

  // After this many failed attempts, an action stops being retried
  // silently on every sync cycle and is parked in the dead-letter queue —
  // otherwise one permanently-broken action (bad data, a stale validation
  // rule) would keep the sync banner stuck on "paused" forever even though
  // the rest of the queue is healthy. Higher than SyncEngine's
  // _maxSilentFailures (3) so the user sees "paused" and gets a chance to
  // notice/retry before the action is given up on automatically.
  static const int _deadLetterThreshold = 5;

  Future<bool>? _pendingSyncInFlight;

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
      SyncManager.instance.startSync('Fetching latest from cloud...');
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
        SyncManager.instance.completeSync();
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
      'outletId': updatedJson['outletId'] ?? _localCache.getActiveOutletId(),
      'queuedAt': DateTime.now().toIso8601String(),
    });

    // Banner state is left to SyncEngine.trigger(), which the caller always
    // invokes right after this returns. Setting it here too, only to have
    // trigger() immediately overwrite it with its own message, was producing
    // a visible flicker between two different banner texts for one event.

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
      'outletId': updatedJson['outletId'] ?? _localCache.getActiveOutletId(),
      'queuedAt': DateTime.now().toIso8601String(),
    });

    // Banner state is left to SyncEngine.trigger(), which the caller always
    // invokes right after this returns — see the matching note in
    // updateStatus() above.

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
  ///
  /// The general order sync paths (bulk-sync action results, the delta
  /// pull) never carry invoice data — it only ever comes back from this
  /// endpoint. So once the server returns it here, it must be merged into
  /// the cached order directly; otherwise the invoice number the server
  /// just generated is fetched once and then discarded, and stays missing
  /// from the order everywhere else in the app reads it from cache.
  Future<InvoiceInfo> getOrCreateInvoice(String orderCode) async {
    final response = await _apiClient.get(ApiEndpoints.orderInvoice(orderCode));
    if (response is Map) {
      final invoice = InvoiceInfo.fromJson(Map<String, dynamic>.from(response));
      await _mergeInvoiceIntoCachedOrder(orderCode, invoice);
      return invoice;
    }
    throw Exception('Failed to generate invoice');
  }

  Future<void> _mergeInvoiceIntoCachedOrder(
    String orderCode,
    InvoiceInfo invoice,
  ) async {
    final cached = _localCache.getCachedOrders();
    if (cached == null) return;
    final index = cached.indexWhere(
      (c) => c['id'] == orderCode || c['orderCode'] == orderCode,
    );
    if (index == -1) return;
    cached[index] = {...cached[index], 'invoice': invoice.toJson()};
    await _localCache.setCachedOrders(cached);
  }

  /// Self-heals any order that reached "paid in full + delivered" but never
  /// got a real invoice — e.g. the one-shot fire-and-forget call after
  /// payment/handover happened to run while offline and was silently
  /// dropped, with nothing left to retry it. Invoice numbers are always
  /// server-assigned (confirmed idempotent/lazy server-side — see
  /// getOrCreateInvoice); this never fabricates one locally, it only
  /// re-asks the server for orders the cache shows as still missing one.
  /// Called after every successful sync cycle by SyncEngine.
  Future<void> retryMissingInvoices() async {
    final cached = _localCache.getCachedOrders();
    if (cached == null) return;
    for (final raw in cached) {
      final Order order;
      try {
        order = Order.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {
        continue;
      }
      if (order.isDelivered && order.isPaidInFull && order.invoice == null) {
        try {
          await getOrCreateInvoice(order.orderCode);
        } catch (_) {
          // Still offline/unreachable — will be retried on the next
          // successful sync cycle.
        }
      }
    }
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
  /// Safe to call concurrently — overlapping callers share the one run
  /// already in flight instead of both reading/writing the local queue at
  /// once. (SyncEngine already guarantees single-flight via its own
  /// `_inFlight` guard; this is a second, independent guard directly on
  /// the repository so the method stays safe for any future caller too.)
  Future<bool> processPendingSyncQueue() {
    final existing = _pendingSyncInFlight;
    if (existing != null) return existing;
    final future = _processPendingSyncQueueImpl();
    _pendingSyncInFlight = future;
    future.whenComplete(() => _pendingSyncInFlight = null);
    return future;
  }

  Future<bool> _processPendingSyncQueueImpl() async {
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

    // Confirmed order results from this run, keyed by whatever code the
    // action targeted (a placeholder for create_order, the real orderCode
    // for update_status/record_payment). Deliberately NOT applied to a
    // `cached` list snapshot held across the whole run — this run can now
    // span several sequential batch requests, and another writer
    // (PosRepository.createOrderOptimistic(), _applyLocalUpdate() from a
    // concurrent updateStatus/recordPayment) can insert or change an order
    // in the local cache while this is still in flight. Applied to a fresh
    // read of the cache at the very end instead, so that write isn't
    // silently discarded.
    final confirmedOrders = <String, Map<String, dynamic>>{};
    final completedIds = <String>{};
    final lastErrorById = <String, String>{};
    final failCountById = <String, int>{};
    final createdPlaceholders = <String, String>{};
    final forbiddenDeadLetterIds = <String>{};
    var allBatchesOk = true;

    final groups = <String?, List<Map<String, dynamic>>>{};
    for (final action in dueNow) {
      final key = _outletKeyForAction(action);
      (groups[key] ??= <Map<String, dynamic>>[]).add(action);
    }

    // Send the queue as small, sequential batches per outlet group rather than
    // one request for everything — a large offline queue can otherwise take the
    // server longer than the client's 30s timeout to process in a single call.
    // Sequential (not concurrent) so batches don't all hit the timeout
    // window at once on a already-struggling connection.
    for (final groupEntry in groups.entries) {
      final key = groupEntry.key;
      final groupDue = groupEntry.value;

      for (var start = 0; start < groupDue.length; start += _bulkSyncBatchSize) {
        final end = (start + _bulkSyncBatchSize < groupDue.length)
            ? start + _bulkSyncBatchSize
            : groupDue.length;
        final batch = groupDue.sublist(start, end);
        final actions = batch.map(_toBulkSyncAction).toList();

        SyncManager.instance.startSync(
          'Syncing $end of ${groupDue.length} offline changes...',
        );
        AppLogger.log(
          _tag,
          'processPendingSyncQueue(): sending batch ${(start ~/ _bulkSyncBatchSize) + 1} '
          '(${batch.length} action(s), $start-${end - 1} of ${groupDue.length})',
        );

        try {
          final response = await _apiClient.post(
            ApiEndpoints.ordersBulkSync,
            body: {'actions': actions},
            headers: {'X-Outlet-Id': key ?? kNoOutletHeader},
          );

          final rawResults = (response is Map ? response['results'] : null);
          final resultsById = <String, Map<String, dynamic>>{
            for (final r in (rawResults is List ? rawResults : <dynamic>[]))
              if (r is Map && r['clientActionId'] != null)
                r['clientActionId'].toString(): Map<String, dynamic>.from(r),
          };

          for (final action in batch) {
            final clientActionId = action['clientActionId']?.toString();
            try {
              final result = clientActionId != null
                  ? resultsById[clientActionId]
                  : null;

              if (result == null || result['status'] != 'success') {
                if (clientActionId != null) {
                  final currentFailCount =
                      (action['failCount'] as num?)?.toInt() ?? 0;
                  failCountById[clientActionId] = currentFailCount + 1;
                  if (result != null && result['error'] != null) {
                    lastErrorById[clientActionId] = result['error'].toString();
                  }
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
                if (placeholderCode.isNotEmpty) {
                  confirmedOrders[placeholderCode] = confirmedOrder.toJson();
                }

                if (action['type'] == 'create_order' &&
                    placeholderCode.isNotEmpty) {
                  createdPlaceholders[placeholderCode] = confirmedOrder.id;
                }
              }
            } catch (e) {
              // The HTTP request itself succeeded — this is a client-side bug
              // processing this one action's result (unexpected payload
              // shape), not a network/connectivity failure. Count just this
              // action as failed rather than letting it look like the whole
              // batch/request failed.
              AppLogger.log(
                _tag,
                'processPendingSyncQueue(): failed to process result for '
                'action $clientActionId',
                error: e,
              );
              if (clientActionId != null) {
                final currentFailCount =
                    (action['failCount'] as num?)?.toInt() ?? 0;
                failCountById[clientActionId] = currentFailCount + 1;
              }
            }
          }

          // A create_order in this batch may have just resolved a placeholder
          // (e.g. LOCAL-1007) that a later, not-yet-sent action in this same
          // run still targets (its update_status/record_payment). Before that
          // action goes into its own batch, rewrite it to the real order id —
          // each batch is now a separate request, so the server's own
          // same-request placeholder resolution (which the old single-request
          // design relied on) no longer reaches across batches.
          if (createdPlaceholders.isNotEmpty) {
            for (final futureAction in dueNow) {
              final type = futureAction['type'];
              if (type != 'update_status' && type != 'record_payment') continue;
              final ref = futureAction['orderCode']?.toString();
              if (ref != null && createdPlaceholders.containsKey(ref)) {
                futureAction['orderCode'] = createdPlaceholders[ref]!;
              }
            }
          }
        } catch (e) {
          if (e is AuthException && e.code == 'FORBIDDEN') {
            AppLogger.log(
              _tag,
              'processPendingSyncQueue(): 403 FORBIDDEN on outlet '
              '${key ?? kNoOutletHeader}, dead-lettering group',
              error: e,
            );
            for (final action in groupDue.sublist(start)) {
              final id = action['clientActionId']?.toString();
              if (id != null && id.isNotEmpty) {
                forbiddenDeadLetterIds.add(id);
                lastErrorById[id] = 'outlet access changed';
              }
            }
            break;
          }
          // This batch failed outright — stop sending further batches for this
          // group. Whatever earlier batches already succeeded stays applied
          // below; this batch's and any later batches' actions in this group
          // simply remain queued for the next sync attempt, same as a
          // single-request failure used to leave the whole queue untouched.
          AppLogger.log(
            _tag,
            'processPendingSyncQueue(): batch starting at $start failed',
            error: e,
          );
          final reallyOffline = await ConnectivityService.instance
              .checkIsOffline();
          if (reallyOffline) {
            SyncManager.instance.setOffline(queue.length);
          } else {
            SyncManager.instance.setError('Sync failed — tap to retry');
          }
          allBatchesOk = false;
          break;
        }
      }
    }

    // Merge this run's confirmed results into a *fresh* read of the cache,
    // not the `cached` list captured before any of the network calls above —
    // this run can span several sequential batch requests, during which
    // another writer (a new order, a concurrent status/payment update) can
    // have already changed the cache. Reading fresh here and merging with
    // no `await` in between keeps this atomic from the event loop's
    // perspective, so that other write can't land in the gap and get lost.
    if (confirmedOrders.isNotEmpty) {
      final freshCached = _localCache.getCachedOrders() ?? [];
      for (final entry in confirmedOrders.entries) {
        final idx = freshCached.indexWhere(
          (c) => c['id'] == entry.key || c['orderCode'] == entry.key,
        );
        if (idx != -1) {
          freshCached[idx] = entry.value;
        } else if (_localCache.isAllOutletsScope() ||
            entry.value['outletId'] == _localCache.getActiveOutletId()) {
          freshCached.insert(0, entry.value);
        }
      }
      await _localCache.setCachedOrders(
        LocalCacheService.dedupeOrdersById(freshCached),
      );
    }

    // Re-read the queue rather than writing back the `dueNow`/`otherStore`
    // snapshot taken at the top of this call — another action (e.g. a
    // second order created while this request was in flight) can have
    // been enqueued in the meantime, and blindly overwriting with the
    // stale snapshot would silently discard it.
    final currentQueue = _localCache.getPendingSyncQueue();
    final updatedQueue = currentQueue
        .map((a) {
          var updated = a;
          final id = a['clientActionId']?.toString();
          if (id != null) {
            if (failCountById.containsKey(id)) {
              updated = {...updated, 'failCount': failCountById[id]};
            }
            if (lastErrorById.containsKey(id)) {
              updated = {...updated, 'lastError': lastErrorById[id]};
            }
          }
          final type = updated['type'];
          if (type == 'update_status' || type == 'record_payment') {
            final ref = updated['orderCode']?.toString();
            if (ref != null && createdPlaceholders.containsKey(ref)) {
              updated = {...updated, 'orderCode': createdPlaceholders[ref]!};
            }
          }
          return updated;
        })
        .where((a) {
          final id = a['clientActionId']?.toString();
          return id == null || !completedIds.contains(id);
        })
        .toList();

    // Actions that have now failed _deadLetterThreshold times in a row (or
    // hit a 403 FORBIDDEN on their outlet group) stop being retried on every
    // sync cycle — parked in a separate queue so they stop counting toward
    // "is anything still stuck?" for the banner.
    final remaining = <Map<String, dynamic>>[];
    final newlyDeadLettered = <Map<String, dynamic>>[];
    for (final a in updatedQueue) {
      final id = a['clientActionId']?.toString();
      final failCount = (a['failCount'] as num?)?.toInt() ?? 0;
      if ((id != null && forbiddenDeadLetterIds.contains(id)) ||
          failCount >= _deadLetterThreshold) {
        newlyDeadLettered.add(a);
      } else {
        remaining.add(a);
      }
    }
    await _localCache.setPendingSyncQueue(remaining);
    if (newlyDeadLettered.isNotEmpty) {
      AppLogger.log(
        _tag,
        'processPendingSyncQueue(): moving ${newlyDeadLettered.length} '
        'action(s) to dead-letter queue',
      );
      final currentDeadLetter = _localCache.getDeadLetterQueue();
      await _localCache.setDeadLetterQueue([
        ...currentDeadLetter,
        ...newlyDeadLettered,
      ]);
    }

    return allBatchesOk;
  }

  String? _outletKeyForAction(Map<String, dynamic> action) {
    final direct = action['outletId'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;
    if (action['type'] == 'create_order') {
      final body = action['body'];
      if (body is Map) {
        final fromBody = body['outletId'] as String?;
        if (fromBody != null && fromBody.isNotEmpty) return fromBody;
      }
      return null;
    }
    if (action.containsKey('outletId')) {
      return null;
    }
    final active = _localCache.getActiveOutletId();
    return (active != null && active.isNotEmpty) ? active : null;
  }

  /// Gives every dead-lettered action one fresh attempt. Only called from a
  /// deliberate user "Sync now"/"Retry" tap — whatever caused an action to
  /// be parked (bad data, a since-fixed server bug) may no longer apply,
  /// but only an explicit user action should pay the cost of re-attempting
  /// something that already failed repeatedly, not every silent background
  /// sync.
  Future<void> reviveDeadLetterQueue() async {
    final deadLetter = _localCache.getDeadLetterQueue();
    if (deadLetter.isEmpty) return;
    AppLogger.log(
      _tag,
      'reviveDeadLetterQueue(): reviving ${deadLetter.length} action(s)',
    );
    final revived = deadLetter.map((a) => {...a, 'failCount': 0}).toList();
    final pending = _localCache.getPendingSyncQueue();
    await _localCache.setPendingSyncQueue([...pending, ...revived]);
    await _localCache.setDeadLetterQueue([]);
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
          final pendingSnapshot = _localCache.getPendingSyncQueue();
          final droppedClientActionIds = <String>{};

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
          final hasPendingCreates = pendingSnapshot.any(
            (a) => a['type'] == 'create_order',
          );
          for (final raw in rawOrders) {
            try {
              final json = Map<String, dynamic>.from(raw as Map);
              final deleted = json['deleted'] == true;
              final orderId = json['id']?.toString() ?? '';
              final orderCode = json['orderCode']?.toString() ?? orderId;
              final idx = cached.indexWhere((c) => c['id'] == orderId);
              if (deleted) {
                if (idx != -1) cached.removeAt(idx);
                // Target order was deleted/cancelled server-side.
                // Drop all pending actions targeting this order (server state wins).
                for (final action in pendingSnapshot) {
                  final ref = action['orderCode']?.toString();
                  if (ref != null && (ref == orderId || ref == orderCode)) {
                    final id = action['clientActionId']?.toString();
                    if (id != null && id.isNotEmpty) {
                      droppedClientActionIds.add(id);
                    }
                  }
                }
                continue;
              }
              if (idx != -1) {
                cached[idx] = json;
              } else if (!hasPendingCreates) {
                cached.add(json);
              }

              // Reconcile pending actions targeting this order.
              // Server data wins: if server state already satisfies what the
              // action intended, drop it from the queue so it stops retrying.
              final serverStatus = json['status']?.toString();
              final serverPayments =
                  (json['payments'] as List?)
                      ?.whereType<Map>()
                      .map((p) => Map<String, dynamic>.from(p))
                      .toList() ??
                  [];
              final matchedServerPaymentIds = <String>{};

              for (final action in pendingSnapshot) {
                final actionId = action['clientActionId']?.toString();
                if (actionId == null || actionId.isEmpty) continue;
                if (droppedClientActionIds.contains(actionId)) continue;

                final ref = action['orderCode']?.toString();
                if (ref == null || (ref != orderId && ref != orderCode)) {
                  continue;
                }

                final type = action['type'];
                if (type == 'update_status') {
                  final actionStatus = action['status']?.toString();
                  if (actionStatus != null && actionStatus == serverStatus) {
                    droppedClientActionIds.add(actionId);
                  }
                } else if (type == 'record_payment') {
                  final actionAmount = (action['amount'] as num?)?.toInt();
                  final actionMethod = action['method']
                      ?.toString()
                      .trim()
                      .toLowerCase();
                  final actionQueuedAt = action['queuedAt']?.toString();

                  if (actionAmount != null && actionMethod != null) {
                    // Strategy 1 (Preferred): Match payment identifier echoed back by server.
                    final exactMatch = serverPayments.firstWhere((p) {
                      final pId = p['id']?.toString() ?? '';
                      if (matchedServerPaymentIds.contains(pId)) return false;
                      return p['clientActionId']?.toString() == actionId ||
                          pId == actionId;
                    }, orElse: () => <String, dynamic>{});

                    if (exactMatch.isNotEmpty) {
                      final pId = exactMatch['id']?.toString() ?? actionId;
                      matchedServerPaymentIds.add(pId);
                      droppedClientActionIds.add(actionId);
                      continue;
                    }

                    // Strategy 2 (Fallback): Strict 1-to-1 match on amount + method +
                    // date proximity (<= 1 calendar day to account for IST vs UTC timezone).
                    final candidateMatch = serverPayments.firstWhere((p) {
                      final pId = p['id']?.toString() ?? '';
                      if (matchedServerPaymentIds.contains(pId)) return false;
                      final pAmount = (p['amount'] as num?)?.toInt();
                      final pMethod = p['method']
                          ?.toString()
                          .trim()
                          .toLowerCase();
                      if (pAmount != actionAmount || pMethod != actionMethod) {
                        return false;
                      }
                      return _isPaymentDateClose(
                        p['date']?.toString(),
                        actionQueuedAt,
                      );
                    }, orElse: () => <String, dynamic>{});

                    if (candidateMatch.isNotEmpty) {
                      final pId = candidateMatch['id']?.toString() ?? '';
                      if (pId.isNotEmpty) {
                        matchedServerPaymentIds.add(pId);
                      }
                      droppedClientActionIds.add(actionId);
                    }
                  }
                }
              }
            } catch (e) {
              // The GET itself succeeded — this is a client-side bug
              // processing one order's payload (unexpected shape, bad
              // date, etc.), not a network failure. Don't let it abort the
              // whole delta pull or get reported as "unreachable"; just
              // skip this one order and keep reconciling the rest.
              AppLogger.log(
                _tag,
                'syncOrdersDelta(): failed to process one order in the page',
                error: e,
              );
            }
          }
          await _localCache.setCachedOrders(
            LocalCacheService.dedupeOrdersById(cached),
          );

          if (droppedClientActionIds.isNotEmpty) {
            final latestQueue = _localCache.getPendingSyncQueue();
            final pruned = latestQueue.where((a) {
              final id = a['clientActionId']?.toString();
              return id == null || !droppedClientActionIds.contains(id);
            }).toList();
            await _localCache.setPendingSyncQueue(pruned);
          }
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

  /// Checks whether a server payment calendar date matches an action's queued
  /// timestamp within a ±1 calendar day tolerance (to handle timezone differences,
  /// e.g. IST calendar date vs client local time).
  static bool _isPaymentDateClose(
    String? serverDateStr,
    String? actionQueuedAtStr,
  ) {
    if (serverDateStr == null || actionQueuedAtStr == null) return true;
    final serverDate = DateTime.tryParse(serverDateStr);
    final actionDate = DateTime.tryParse(actionQueuedAtStr);
    if (serverDate == null || actionDate == null) {
      if (serverDateStr.length >= 10 && actionQueuedAtStr.length >= 10) {
        return serverDateStr.substring(0, 10) ==
            actionQueuedAtStr.substring(0, 10);
      }
      return true;
    }
    final sDateOnly = DateTime(
      serverDate.year,
      serverDate.month,
      serverDate.day,
    );
    final aDateOnly = DateTime(
      actionDate.year,
      actionDate.month,
      actionDate.day,
    );
    return sDateOnly.difference(aDateOnly).inDays.abs() <= 1;
  }
}
