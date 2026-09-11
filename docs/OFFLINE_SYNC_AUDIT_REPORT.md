# Flutter Offline-First Sync Implementation Code Review & Bug Audit

This report provides the line-by-line code audit and root cause analysis for the two reported sync bugs in `laundry_pos_mobile`, along with minimal proposed fixes and additional edge-case vulnerabilities identified during code tracing.

---

## 1. Executive Summary of Root Causes

| Bug                                                      | Primary Culprit                                                                                                                                                                                                                                                                                                                                                                        | Exact Mechanism                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Bug 1: 2 offline orders created, 3 appear**            | `OrdersRepository.syncOrdersDelta()` ([orders_repository.dart:306-316](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart#L306-L316)) & `processPendingSyncQueue()` ([orders_repository.dart:252-259](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart#L252-L259)) | **Delta Sync Blind Insertion**: `syncOrdersDelta` checks only `c['id'] == json['id']` (e.g. `EL-101`), which fails to match local unsynced placeholders (`LOCAL-xxx`). If delta sync runs before placeholder reconciliation, or if bulk-sync timed out client-side while succeeding server-side, `cached.add(json)` appends the server order as a duplicate alongside the existing `LOCAL-xxx` placeholder. Furthermore, a race in `SyncEngine.trigger()` wipes queued Order #2 actions when Order #1 sync completes. |
| **Bug 2: Banner still shows "Sync now" / doesn't clear** | `OrdersRepository.processPendingSyncQueue()` ([orders_repository.dart:180-182](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart#L180-L182)) & `SyncEngine._runSync()` ([sync_engine.dart:53-56](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/core/sync/sync_engine.dart#L53-L56))                        | **State Machine Never Transitions to Synced on Empty Queue or Delta Pull**: When the push queue is empty (0 local writes), `processPendingSyncQueue()` short-circuits with `return true` without calling `SyncManager.instance.completeSync()`. `SyncEngine._runSync()` also never touches `SyncManager` on success. Additionally, any 400 validation error permanently leaves the action in `pendingSyncQueue`, trapping `SyncManager` in `setOffline` indefinitely.                                                 |

---

## 2. Deep Dive: Bug 1 (Created 2 Offline Orders, 3 Show Up)

### 2.1. Exact Code Paths Traced

1. `lib/features/pos/data/pos_repository.dart`: `createOrderOptimistic()` (lines 104–170)
2. `lib/core/sync/sync_engine.dart`: `trigger()` & `_runSync()` (lines 27–68)
3. `lib/features/orders/data/orders_repository.dart`: `processPendingSyncQueue()` (lines 179–279)
4. `lib/features/orders/data/orders_repository.dart`: `syncOrdersDelta()` (lines 290–330)

### 2.2. Root Cause Analysis

#### Cause A: Delta Sync Blind Insertion (`syncOrdersDelta()`)

- **Location**: [lib/features/orders/data/orders_repository.dart:306-316](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart#L306-L316)

```dart
final idx = cached.indexWhere((c) => c['id'] == json['id']);
if (deleted) {
  if (idx != -1) cached.removeAt(idx);
  continue;
}
if (idx != -1) {
  cached[idx] = json;
} else {
  cached.add(json);  // <-- DUPLICATION SITE
}
```

- **Execution Flow**:
  1. Two orders are placed offline. They exist in local cache as:
     `[{'id': 'LOCAL-1001', ...}, {'id': 'LOCAL-1002', ...}]`.
  2. In `SyncEngine._runSync()`:
     ```dart
     final pushOk = await _ordersRepository.processPendingSyncQueue();
     final pullOk = pushOk ? await _ordersRepository.syncOrdersDelta() : true;
     ```
  3. If `processPendingSyncQueue()` fails on the client (e.g. network timeout or connection reset right after the server committed the transaction), the local placeholders are **not replaced**.
  4. On reconnect or subsequent sync, `syncOrdersDelta()` queries `GET /api/v1/orders/sync`. The server returns `[{'id': 'EL-101', ...}, {'id': 'EL-102', ...}]`.
  5. `syncOrdersDelta()` performs `cached.indexWhere((c) => c['id'] == json['id'])`. Since `c['id']` is `LOCAL-1001` / `LOCAL-1002`, `idx` is `-1`.
  6. It invokes `cached.add(json)`.
  7. **Result**: The local cache now contains:
     - `LOCAL-1001` (placeholder)
     - `LOCAL-1002` (placeholder)
     - `EL-101` (server copy of Order 1)
       **Total = 3 orders displayed on the screen.**

#### Cause B: Re-insertion in `processPendingSyncQueue()`

- **Location**: [lib/features/orders/data/orders_repository.dart:252-259](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart#L252-L259)

```dart
final idx = cached.indexWhere(
  (c) => c['id'] == placeholderCode || c['orderCode'] == placeholderCode,
);
if (idx != -1) {
  cached[idx] = confirmedOrder.toJson();
} else {
  cached.insert(0, confirmedOrder.toJson());  // <-- ADDS INSTEAD OF REPLACING
}
```

- If delta sync already inserted `EL-101` (from Cause A), or if `placeholderCode` is missing/mismatched in cache, `idx` evaluates to `-1`. The `else` branch calls `cached.insert(0, confirmedOrder.toJson())`, generating a second duplicate of the same order.

#### Cause C: Queue Wipe Race Condition in `SyncEngine.trigger()`

- **Location**: [lib/core/sync/sync_engine.dart:28-34](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/core/sync/sync_engine.dart#L28-L34) and [lib/features/orders/data/orders_repository.dart:264-265](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart#L264-L265)
- When Order #1 triggers `_runSync()`, `processPendingSyncQueue()` snapshots `dueNow = [action1]` and awaits `_apiClient.post()`.
- While that HTTP call is in flight, the user creates Order #2. `PosRepository.createOrderOptimistic()` adds `action2` to Hive and calls `SyncEngine.instance.trigger()`.
- `SyncEngine.trigger()` sees `_inFlight != null` and simply returns the in-flight Future without scheduling a follow-up run.
- When the Order #1 HTTP call completes, line 264 computes `remaining = [...stillPending, ...otherStore]`. Since `dueNow` only contained `action1`, `remaining` is `[]`.
- Line 265 runs `await _localCache.setPendingSyncQueue(remaining)`.
- **Result**: `action2` is permanently wiped from Hive before it is ever sent to the server.

---

## 3. Deep Dive: Bug 2 (Banner Still Shows "Sync Now" / Doesn't Clear)

### 3.1. Exact Code Paths Traced

1. `lib/features/orders/data/orders_repository.dart`: `processPendingSyncQueue()` (lines 180–198, 267–278)
2. `lib/core/sync/sync_engine.dart`: `_runSync()` (lines 42–68)
3. `lib/features/orders/presentation/orders_list_screen.dart`: `_refreshAndAwait()` & `SyncStatusBar(onSyncNow)` (lines 143–145, 275–279)
4. `lib/features/orders/bloc/orders_bloc.dart`: `_onRefreshOrders()` (lines 46–54)
5. `lib/shared/widgets/sync_status_bar.dart`: `_handleSyncChange()` (lines 32–48)

### 3.2. Root Cause Analysis

#### Cause A: Empty Queue Short-Circuit Leaves `SyncManager` in Offline/Paused State

- **Location**: [lib/features/orders/data/orders_repository.dart:180-182](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart#L180-L182) and [lib/core/sync/sync_engine.dart:53-56](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/core/sync/sync_engine.dart#L53-L56)
- When connectivity resumes, or when a user taps "Sync now" / "Retry", the banner is in `SyncStatus.offline` or `SyncStatus.syncPaused`.
- If `_localCache.getPendingSyncQueue()` is empty:
  ```dart
  final queue = _localCache.getPendingSyncQueue();
  if (queue.isEmpty) return true;
  ```
  It returns `true` immediately without touching `SyncManager`.
- In `SyncEngine._runSync()`:
  ```dart
  if (ok) {
    _failureStreak = 0;
    return; // <-- Does not call completeSync()
  }
  ```
- `SyncManager.instance.completeSync()` is **never called**.
- `SyncManager` remains stuck in `SyncStatus.offline` or `SyncStatus.syncPaused`. The banner never clears.

#### Cause B: Permanent Queue Poisoning from Unhandled Action Rejection

- **Location**: [lib/features/orders/data/orders_repository.dart:237-244, 270](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart#L237-L244)
- In the backend `bulkSyncOrders()` ([orders.ts:291-301](file:///Users/reddygona/Documents/skills/laundry_pos/src/server/services/orders.ts#L291-L301)), if an action fails (e.g. validation error, deleted product, deactivated payment method), the server returns `status: 'failed'`.
- In `processPendingSyncQueue()`:
  ```dart
  if (result == null || result['status'] != 'success') {
    stillPending.add(action); // <-- Left in queue forever
    continue;
  }
  ...
  SyncManager.instance.setOffline(remaining.length);
  ```
- The rejected action is never pruned and has no retry count limit. Every subsequent sync pass keeps `remaining.length > 0`, calling `SyncManager.instance.setOffline(remaining.length)`.
- The banner permanently displays `"Offline · 1 change saved locally · Sync now"`.

#### Cause C: User "Retry" / "Sync Now" Tap Does Not Reset Failure Streak

- **Location**: [lib/features/orders/presentation/orders_list_screen.dart:144](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/presentation/orders_list_screen.dart#L144)
- `SyncStatusBar` calls `_refreshAndAwait(context)`, which dispatches `RefreshOrdersEvent()`.
- `OrdersBloc._onRefreshOrders()` calls `SyncEngine.instance.trigger()`, **not `SyncEngine.instance.retryNow()`**.
- `SyncEngine.retryNow()` was specifically created to reset `_failureStreak = 0`.
- Calling `trigger()` leaves `_failureStreak >= 3`. If `syncOrdersDelta()` hits any minor glitch or returns `false`, `_runSync()` immediately re-executes `SyncManager.instance.setSyncPaused()`, locking the banner back into `"Sync paused — tap to retry"`.

---

## 4. Minimal Proposed Fixes

### Fix 1: In `lib/core/sync/sync_engine.dart`

1. Re-trigger if another sync was requested while in flight (prevents action loss).
2. Ensure `SyncManager` is updated when the sync run completes cleanly.

```dart
class SyncEngine {
  ...
  bool _hasPendingTrigger = false;

  Future<void> trigger() {
    if (_inFlight != null) {
      _hasPendingTrigger = true;
      return _inFlight!;
    }

    final future = _runSync();
    _inFlight = future;
    future.whenComplete(() {
      _inFlight = null;
      if (_hasPendingTrigger) {
        _hasPendingTrigger = false;
        trigger();
      }
    });
    return future;
  }

  Future<void> _runSync() async {
    var ok = false;
    try {
      final pushOk = await _ordersRepository.processPendingSyncQueue();
      final pullOk = pushOk ? await _ordersRepository.syncOrdersDelta() : true;
      ok = pushOk && pullOk;
    } catch (_) {
      ok = false;
    }

    if (ok) {
      _failureStreak = 0;
      final pendingCount = _localCache.getPendingSyncQueue().length;
      if (pendingCount == 0) {
        SyncManager.instance.completeSync();
      } else {
        SyncManager.instance.setOffline(pendingCount);
      }
      return;
    }

    _failureStreak++;
    if (_failureStreak >= _maxSilentFailures) {
      var pendingCount = 0;
      try {
        pendingCount = _localCache.getPendingSyncQueue().length;
      } catch (_) {}
      SyncManager.instance.setSyncPaused(pendingCount);
    }
  }
}
```

### Fix 2: In `lib/features/orders/data/orders_repository.dart`

1. When updating `pendingSyncQueue`, only remove actions that succeeded; do not overwrite concurrent writes.
2. Deduplicate incoming server orders in `syncOrdersDelta` against unsynced local placeholders.
3. Replace by confirmed order `id` or placeholder code in `processPendingSyncQueue`.

```dart
// In processPendingSyncQueue():
// Update confirmed orders:
final idx = cached.indexWhere(
  (c) => c['id'] == placeholderCode || c['orderCode'] == placeholderCode || c['id'] == confirmedOrder.id,
);
if (idx != -1) {
  cached[idx] = confirmedOrder.toJson();
} else {
  cached.insert(0, confirmedOrder.toJson());
}

// Preserve concurrent items in queue:
final completedActionIds = dueNow
    .where((a) => resultsById[a['clientActionId']?.toString()]?['status'] == 'success')
    .map((a) => a['clientActionId']?.toString())
    .toSet();
final currentQueue = _localCache.getPendingSyncQueue();
final remaining = currentQueue.where((a) => !completedActionIds.contains(a['clientActionId']?.toString())).toList();
await _localCache.setPendingSyncQueue(remaining);

if (remaining.isEmpty) {
  SyncManager.instance.completeSync();
} else {
  SyncManager.instance.setOffline(remaining.length);
}
```

```dart
// In syncOrdersDelta():
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
  } else {
    // Check if there is an unsynced local placeholder for this order
    final placeholderIdx = cached.indexWhere((c) =>
        (c['id']?.toString().startsWith('LOCAL-') ?? false) &&
        c['phone'] == json['phone'] &&
        c['date'] == json['date']);
    if (placeholderIdx != -1) {
      cached[placeholderIdx] = json;
    } else {
      cached.add(json);
    }
  }
}
```

### Fix 3: In `lib/features/orders/presentation/orders_list_screen.dart`

Reset the failure streak on manual user tap:

```dart
SyncStatusBar(
  onSyncNow: () {
    SyncEngine.instance.retryNow();
    _refreshAndAwait(context);
  },
),
```

---

## 5. Other Suspicious Areas & Edge Cases Flagged

1. **Missing HTTP Client Timeouts** ([api_client.dart:46-91](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/core/network/api_client.dart#L46-L91)):
   `http.Client.post()` does not specify a timeout. Unreachable backend endpoints will hang for OS-level TCP connect timeouts (60–75 seconds), locking `_inFlight` in `SyncEngine` and making the entire app appear frozen.
   _Recommendation_: Add `.timeout(const Duration(seconds: 15))` to all HTTP calls in `ApiClient`.

2. **Dead-Letter Queue Missing for 400 Validation Errors**:
   Currently, an action rejected by `POST /bulk-sync` with a permanent 400 validation error (e.g. service deleted) is retained indefinitely in `pendingSyncQueue`.
   _Recommendation_: Add a `retryCount` to queued actions. After 3 attempts with non-network errors, move the action to an error log / dead-letter queue and notify the user.

3. **Placeholder Sort Key Equality Collision** ([orders_repository.dart:36-40](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart#L36-L40)):
   `_orderSortKey` returns `1 << 30` for all `LOCAL-xxx` orders. Dart's `sort()` does not guarantee stability for identical keys across list modifications. Placeholders can shuffle order after every cache save.
   _Recommendation_: Fall back to comparing `DateTime.tryParse(order.date)` when sort keys match.
