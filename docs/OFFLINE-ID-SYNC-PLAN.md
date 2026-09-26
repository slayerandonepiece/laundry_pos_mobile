# Offline ids, sync screen and local-first screens: plan and findings

Status: **planned, backend part implemented (uncommitted → now committed on
`laundry_pos` branch `backend/offline-id`), app part not started on
`laundry_pos_mobile` branch `frontend/offline-id`.**
Written 2026-09-26. Check git before trusting any "done" claim here.

"Store" in the user's wording = **outlet** in code. The backend `Store` table
is the organization; it has `Outlet`s.

---

## 1. The user's request (verbatim, 2026-09-26)

> When loggedin
> Store Owner
> * Fetching Organization & Stores
> * Syncing Stores Data
> * Syncing Prices
> * Syncing Products
> * Syncing Orders
>
> etc what ever needed
>
> for Employee
> it should be
> login ->
> Store Selection
> * if one store skip it & show syncing screen
> * else ask user to select store & remeber this
>
> then fetch the data
>
> Note: when ever user moves to new screen always load local data, unless user
> pull to refresh or clicks on reload button
>
> Next
> when syncing offline data, it's not possible to keep track changes and avoid
> duplicates so we need to maintain 2id's
> id, offline_id
> order created from app, id will be empty and offline id should be unique
> when synced based on id it should refect
> same when online orders created from website offline_id will be empty
> but when user make changes in app it will be assigned if not there
>
> go through the code, check everything
> come up with impl plan

---

## 2. Bugs found in the current offline sync (not yet fixed)

1. **Setup screen wipes the local orders list.**
   `BootstrapScreen` → `OrdersRepository.fetchRecentOrders(limit: 30)` →
   `setCachedOrders(orders)` replaces the whole cached list. Unsynced orders
   vanish from the list (they're still queued), anything older than 30 is
   dropped, and the sync cursor is not reset, so dropped orders only return
   when they next change on the server.
2. **Other devices' new orders can disappear for good.**
   `syncOrdersDelta` skips inserting any not-yet-cached order while *any*
   `create_order` is queued (`hasPendingCreates`), but still advances the
   cursor past it. It never appears until someone edits it.
3. **No link back from a synced order to its offline placeholder.** The
   server never returned the client's id, so a lost reply to a create left
   the `LOCAL-…` row and the real `EL-…` row unreconciled. Bug 2 is the
   workaround for this.
4. **Offline payments matched by guesswork** (amount + method + date within
   ±1 day) because payment `clientActionId` wasn't returned.
5. **Remembered outlet is forgotten on logout.** `logout()` →
   `LocalCacheService.clear()` wipes everything, including the outlet choice.

Also noted: dashboard preset periods send no dates (known, pre-existing).

---

## 3. Phase 1 — two ids per order (`id` + `offlineId`)

### 3.1 Backend (`laundry_pos`) — DONE on branch `backend/offline-id`

- `prisma/schema.prisma`: `Order.offlineId String?` + `@@unique([storeId, offlineId])`.
  Migration `20260926100000_add_order_offline_id` (verified equal to
  `prisma migrate diff`). Existing rows stay null — no backfill.
  Could not reuse `idempotencyKey`: the web also sets it, and the rule is that
  web orders have no offline id.
- `src/server/services/orders.ts`:
  - `createOrderSchema` / `CreateOrderInput` accept optional `offlineId`
    (trim, 1–64 chars); stored on create.
  - Create is idempotent by `idempotencyKey` (as before) **and** by
    `(storeId, offlineId)`.
  - `toOrderDTO` returns `offlineId` (omitted when null) and each payment's
    `clientActionId`.
  - `bulkSyncOrders`: `orderRef` resolves in order: same-batch create →
    failed same-batch create (skip) → `EL-` code → **DB lookup by
    `offlineId`** → else "Referenced order was not created yet."
- `src/features/admin/admin.types.ts`: `Order.offlineId?`, `Payment.clientActionId?`.
- `.agents/MOBILE-API-CONTRACT.md` §3.5 documents all of this.
- Gates run: `npx tsc --noEmit` clean, `eslint` clean on changed files.
  **Not run:** integration suite (needs Postgres; see backend handoff §5).
- Migration applies on deploy (`vercel-build` runs `prisma migrate deploy`).
  User says auto-deploy on merge is disabled.

### 3.2 App (`laundry_pos_mobile`) — TO DO, detailed design

Order model (`lib/features/orders/data/models/order_model.dart`):
- Add `final String? offlineId` (fromJson: empty → null; toJson; copyWith).
- `id` stays the server code (`EL-123`) and is **empty** for unsynced orders.
- `orderCode` getter becomes the *local key*: `id` if non-empty, else
  `offlineId`. Bloc events and repository calls keep passing `orderCode`.
- Add `displayCode`: `id` if non-empty, else `OFF-` + last 6 chars of
  `offlineId` uppercased. Replace **display** uses of `orderCode` with it
  (list rows, detail header, activity, status/collect dialogs, bill/invoice
  text and file names, PDF builder).
- Add `bool isSameOrder(Order other)`: both ids non-empty → compare `id`;
  else compare non-null `offlineId`.

Matching rule everywhere (repository, cache, blocs):
- A *ref* (string from `orderCode`) matches a cached map when
  `c['id'] == ref || c['offlineId'] == ref`. Replaces every
  `c['id'] == orderCode || c['orderCode'] == orderCode`.
- A server order matches a cached map when ids are equal (non-empty) or its
  `offlineId` equals the cached `offlineId`. When merging, keep the cached
  `offlineId` if the server has none (web order edited in the app).
- `OrdersBloc` `o.id == updated.id` (4 places) → `o.isSameOrder(updated)`
  (with empty ids every unsynced order would otherwise match).
- `order_detail_screen.dart`, `status_dialog.dart`, `collect_payment_dialog.dart`:
  `selectedOrder.orderCode == widget.order.orderCode` → `isSameOrder`, so a
  screen keeps tracking an order after it syncs and its key changes.
- `LocalCacheService.dedupeOrdersById`: collapse rows sharing a non-empty
  `id` **or** a non-null `offlineId` (keep last).

Create (`lib/features/pos/data/pos_repository.dart` `createOrderOptimistic`):
- `offlineId = IdempotencyKeyGenerator.generate()` (UUIDv4) replaces
  `LOCAL-<ms>`; `body['offlineId'] = offlineId`; local `Order(id: '', offlineId: …)`.
- Queue action keeps `offlineCode: offlineId` (bulk-sync schema requires it).

Edits (`OrdersRepository._applyLocalUpdate`):
- If the order has no `offlineId` (web order), assign a UUID — local only
  (recommended; server already knows it by `id`). **Decision pending.**

Queue push (`_processPendingSyncQueueImpl` / `_toBulkSyncAction`):
- `orderRef` = cached order's `id` if known, else the ref (offlineId). The
  server now resolves offlineIds across requests, so **remove the
  `createdPlaceholders` rewrite** (in-batch and at queue write-back).
- Keep the legacy orphan prune (only `LOCAL-`/`OFF-` refs) as is.
- Confirmed results merge into the fresh cache read by the match rule above.

Delta pull (`syncOrdersDelta`):
- Match by `id` or `offlineId`; **remove the `hasPendingCreates` skip** (fixes
  bug 2 — a lost-reply create now reconciles by `offlineId`).
- Deleted orders drop queued actions whose ref is the order's `id` or `offlineId`.
- Payment reconcile already prefers `p['clientActionId']`; server now sends
  it, so the fuzzy fallback becomes a legacy path (leave in place).

Legacy data on phones (one-time, idempotent, at `LocalCacheService.init()`):
- For every `cached_orders_list*` key: rows whose `id` starts `LOCAL-`/`OFF-`
  → `offlineId = id`, `id = ''`.
- Pending + dead-letter queue `create_order`: `body.offlineId ??= offlineCode`.
- Status/payment actions keep their `LOCAL-…` ref (it now equals the offlineId).

Sorting: `_orderSortKey` already puts non-`EL-` ids (now empty) on top — no change.

Tests to add/adapt: lost reply → one order; other device's order arrives while
uploads pending → shown; create + pay offline; web order edited in app;
legacy migration; existing tests asserting `LOCAL-` codes
(`sync_reconciliation_test`, `sync_per_outlet_test`, `sale_flow_test`, …).
Tests must use the Map-backed `FakeLocalCache` inside `testWidgets`.

---

## 4. Phase 2 — setup ("syncing") screen after login

Runs on **fresh login** and on switching to an outlet with an empty cache.
Cold start opens straight from local data.

Owner steps: 1 Fetching organization & outlets (`refreshOutletContext` /
`auth/status`) · 2 Store details · 3 Services & prices (`/products` — one API;
show as one or two rows, **decision pending**) · 4 Payment methods ·
5 Upload pending changes, then full orders pull (delta from empty cursor,
merged — replaces `fetchRecentOrders`, fixes bug 1) · 6 Dashboard ·
7 Expenses · 8 Staff.

Employee: login → outlet pick (exists: auto-skip with one outlet,
`OutletRequiredScreen` otherwise) → steps 3, 4, 5 for that outlet.

Remember the outlet across logout: store it under a key `clear()` preserves,
keyed by user + organization (bug 5).

Keep per-step retry + "Continue anyway" (`bootstrap_screen.dart`).

## 5. Phase 3 — every screen opens with local data only

Already local-only: Orders list (`OrdersBloc._onLoadOrders`), order detail.
To change (cache-only `Load*`, network only via pull-to-refresh / Reload →
new `Refresh*` event): Dashboard, Expenses, Staff, Payment methods, Store
profile, Your details (all `OwnerBloc`), Services (`services_screen`),
New-sale catalogue (`CartBloc LoadCatalogEvent`), Collect-payment method list.
Empty cache → empty state with Reload. `main.dart` outlet-scope listener
should dispatch cache loads only.

Exceptions: background `SyncEngine` push/pull on reconnect/resume stays
(screens re-read cache after); dashboard period change fetches (cache per
period); customer-name lookup asks the server only when the phone has no
local match.

## 6. Decisions

Resolved:
- Build on the outlet work — `chore/backend-and-setup` merged into `main` in
  both repos. One working branch per repo, named per side:
  `frontend/offline-id` (this repo) and `backend/offline-id` (`laundry_pos`).
  Frontend and backend are handled in **separate chats with separate prompts**.
- Claude implements directly (user: "start working on it").

Pending (use the recommendation if the user doesn't say otherwise, and say so):
1. Web order edited in the app: keep its new `offlineId` on the phone only
   (**recommended**) vs also save it on the server.
2. Setup screen: "Prices" and "Products" as one row (**recommended**, same
   API) or two.

## 7. Order of work

Phase 1 app → Phase 2 → Phase 3, each a separate tested batch, committed only
with the user's approval. Gates: `flutter analyze` clean, `flutter test` all
green (baseline **273/273** on `main` c6e3212).
