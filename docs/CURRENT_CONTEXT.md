> **Superseded (2026-09-27).** Historical note from 2026-09-11. Current state:
> `docs/HANDOFF.md` (workspace-improvements batch and merged main baseline).
> Current offline-sync plan: `docs/OFFLINE-ID-SYNC-PLAN.md`.
> New enhancement audit and acceptance checks: `docs/WEB-MOBILE-FEATURE-GAPS.md`.

# Current Context & Offline Sync Status

**Updated:** 2026-09-11
**Repos Involved:**
1. Mobile App: `/Users/reddygona/Documents/skills/laundry_pos_mobile`
2. Web / Backend (Next.js + Prisma): `/Users/reddygona/Documents/skills/laundry_pos`

---

## 1. Problem Statement
When orders are created offline in the mobile app:
1. They display with an "Offline" badge.
2. When the user reconnects to the internet and taps "Sync", the offline orders vanish/get erased instead of syncing to the cloud.

---

## 2. Root Cause Analysis (Identified in Mobile Code)

### Bug 1: Hive Shallow-Copy Drops Nested Data
In [local_cache.dart](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/core/storage/local_cache.dart):
Hive stores objects as `Map<dynamic, dynamic>` and `List<dynamic>`.
`getPendingSyncQueue()` and `getCachedOrders()` only did a shallow `Map<String, dynamic>.from(e as Map)`.
The nested fields like `body['entries']` (e.g. `[{ productId: ..., quantity: ... }]`) remain `Map<dynamic, dynamic>`.
When [orders_repository.dart](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart) reads:
```dart
final body = Map<String, dynamic>.from(action['body'] as Map); // shallow!
```
The nested `entries` list cannot serialize properly for HTTP POST → exception thrown in `processPendingSyncQueue()` → order stays in `remaining` queue and is never synced.

### Bug 2: `listOrders()` Wipes Cache
In [orders_repository.dart](file:///Users/reddygona/Documents/skills/laundry_pos_mobile/lib/features/orders/data/orders_repository.dart):
`listOrders()` calls `setCachedOrders(orders)` directly with server-returned orders. Because the pending order failed to sync due to Bug 1, `listOrders()` overwrote the entire cache with the server list, wiping out local offline orders (`LOCAL-xxx`) from visibility.

---

## 3. Backend Inspection Results (`laundry_pos`)

Inspected `/Users/reddygona/Documents/skills/laundry_pos/src/server/services/orders.ts` & `/Users/reddygona/Documents/skills/laundry_pos/src/app/api/v1/orders/route.ts`:

1. **Idempotency is supported on single order creation:**
   `POST /api/v1/orders` accepts `idempotencyKey: string`. If an order with that `idempotencyKey` already exists in the store, Prisma returns the existing order without duplicating it.
2. **Order listing is flat (no pagination):**
   `GET /api/v1/orders` runs `prisma.order.findMany({ where: { storeId, legacyCancelled: false }, ... })` and returns all store orders.
3. **No bulk endpoint currently exists:**
   There is currently no `POST /api/v1/orders/bulk` endpoint. Orders are submitted individually.

---

## 4. Immediate Mobile Solution (Fixing Bug 1 & 2)

1. **`LocalCacheService`:**
   Add a recursive `deepCopy(dynamic val)` helper to convert all nested Maps to `Map<String, dynamic>` and Lists to deep copies. Apply it in `getCachedOrders()` and `getPendingSyncQueue()`.
2. **`OrdersRepository.processPendingSyncQueue()`:**
   Use `LocalCacheService.deepCopy(action['body'])` so nested `entries` serialize cleanly.
3. **`OrdersRepository.listOrders()`:**
   Instead of wiping the cache with server orders, merge unsynced local orders (`LOCAL-xxx`) that remain in the pending queue with the server orders.

---

## 5. Backend Bulk API Requirements (If Bulk Sync is Preferred)
If we want a single bulk sync endpoint `POST /api/v1/orders/bulk`:
- Accepts: `{ orders: CreateOrderInput[] }`
- Each item must have `idempotencyKey`.
- Returns: `{ synced: Order[], failed: { idempotencyKey: string, error: string }[] }`
