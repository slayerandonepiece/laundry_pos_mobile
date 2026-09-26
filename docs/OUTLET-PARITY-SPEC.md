# Outlet awareness + web parity — implementation spec (Phase 3)

Written 2026-09-26 from the running `../laundry_pos` source, not from
memory. Every contract below was read out of the route handler that
serves it; file:line references point into the web repo so you can
re-check rather than trust this file.

This spec exists because the mobile app was built before the
multi-outlet rollout (backend tasks B1–B6, workspace W1–W2) landed.
`grep -ril outlet lib/` currently returns **0 files**. Everything else
in this document follows from that one fact.

> **Updated 2026-09-26.** The backend work this spec asked for has been
> done. The authoritative API contract now lives at
> `../laundry_pos/.agents/MOBILE-API-CONTRACT.md` — read that first; it
> is generated from the server code and carries file:line citations.
> Where the two disagree, the contract file wins.

Read with: `docs/DESIGN-SPEC.md` (design system), `TASKS.md` (phase
history), `../laundry_pos/.agents/CURRENT-STATE.md` (backend truth).

---

## O0 — Decisions and prerequisites

Confirm these before building the affected screens. Do not guess.

| # | Decision | Default | Blocks |
| --- | --- | --- | --- |
| O0.1 | Does the owner get an **All outlets** scope, and on which screens? | Dashboard + Orders + Expenses only, never New sale (mirrors web) | O3, O5, O6 |
| O0.2 | Employee with **zero** allowed outlets | Blocking screen, no order screens at all | O4 |
| O0.3 | Outlet access revoked while signed in | Force re-authentication (see O0.B) | O2, O7 |
| O0.4 | Does `Ready` move from amber to violet? | Yes, matches web `statusTone()` | O8 |
| O0.5 | Pre-select a payment method at checkout? | **No.** Payments are irreversible — there is no void/refund path in the backend. "Place order" stays disabled until tapped. | O5.5 |

### O0.A — Backend payment-methods change: **DONE (2026-09-26)**

`GET /api/v1/payment-methods` now returns enabled **organization**
methods (`{id, code, name, enabled}`), `?all=true` returns disabled ones
too, `PATCH /{id}` toggles `enabled`, and `POST` is retired (410).
Renaming returns 400 — names live in the platform catalogue.

Two consequences for this app:

- **Delete the Add and Rename payment-method screens.** The endpoints
  behind them are gone. Only the enable/disable toggle remains.
- `id` is now the *platform* method id, and it is the id `PATCH` takes.

One thing no API change can fix: an organization with **zero enabled
methods** (One Wash, in the dev data) can take no prepaid order and
collect no balance. The owner must enable one. Handle the empty list
per O5.5 rather than falling back to a literal "Cash".

### O0.B — Outlet context on cold start: **DONE (2026-09-26)**

`GET /api/v1/auth/status` and `GET /api/v1/memberships` now return the
same outlet context as login, so the app can refresh `allowedOutlets`
on every launch instead of only at sign-in. The cache-then-403 fallback
described below is still worth keeping as a safety net, but it is no
longer the primary path.

---

## O1 — What the API already gives you

All verified against source. No new endpoints are needed.

### Outlet identification

`resolveOutletIdFromRequest`
([handler.ts:88-99](../../laundry_pos/src/server/api/handler.ts)) accepts,
in order:

1. `X-Outlet-Id` request header (case-insensitive)
2. `?outletId=` query parameter

**Use the header everywhere except `/api/v1/dashboard`**, which reads
its own `?outletId=` query param directly and ignores the header
([dashboard/route.ts:15](../../laundry_pos/src/app/api/v1/dashboard/route.ts)).

### Which routes require it

| Route | `OWNER` | `EMPLOYEE` |
| --- | --- | --- |
| `GET /api/v1/orders` | optional — omit = whole org | **required, else 403** |
| `POST /api/v1/orders` | optional (also accepts `body.outletId`) | **required, else 403** |
| `GET /api/v1/orders/sync` | optional | **required, else 403** |
| `POST /api/v1/orders/bulk-sync` | optional | **required**; every `create_order` action whose `payload.outletId` differs from the header is rejected `403` |
| `GET /api/v1/dashboard` | `?outletId=` optional | OWNER-only route |
| `GET /api/v1/dashboard/rollups` | optional | **required, else 403** |
| `GET,POST /api/v1/expenses` | optional | OWNER-only route |
| everything else | not outlet-scoped | not outlet-scoped |

Source: [orders/route.ts:32,55](../../laundry_pos/src/app/api/v1/orders/route.ts),
[orders/sync/route.ts:40](../../laundry_pos/src/app/api/v1/orders/sync/route.ts),
[orders/bulk-sync/route.ts:21-33](../../laundry_pos/src/app/api/v1/orders/bulk-sync/route.ts),
[expenses/route.ts:15,25](../../laundry_pos/src/app/api/v1/expenses/route.ts).

The employee gate is deliberate, quoted from the handler: *"Never
silently fall back to a default outlet: employees must name the active
outlet for every operational read, preventing legacy/null data from
leaking into an outlet-scoped mobile cache."* Do not ask for it to be
relaxed.

**This is why employee sign-in is broken on mobile today.** Sending the
header is the whole fix for O2.

### Outlet precedence, and the fallback that surprises people

`createOrder` resolves the outlet as
`headerOutletId ?? body.outletId ?? <oldest ACTIVE outlet of the store>`.

- **The header wins over the body.** Since 2026-09-26 a *conflict*
  between the two is a 400 rather than a silent win, but where only one
  is present that one is used.
- **An order with no outlet at all is auto-assigned to the oldest active
  outlet — it does not become organization-wide.** Every order this app
  has created so far went there. Unchanged by this round; always send an
  outlet explicitly so it never applies.

An *existing* order whose stored `outletId` is null is genuinely
organization-wide, and reads as `Organization-wide`. Writing and reading
differ here; don't conflate them.

### Login response (the source of outlet truth)

`POST /api/v1/auth/login` → 200:

```jsonc
{
  "token": "<43-char base64url>",
  "user": { "id", "name", "username", "isSuperAdmin", "mustChangePassword" },
  "stores": [ /* legacy flat list — what this app reads today */ ],
  "organizations": [
    {
      "id": "<storeId>",
      "name": "One Wash Laundry",
      "role": "OWNER" | "EMPLOYEE",
      "status": "ACTIVE" | "LOCKED",
      "isLocked": false,
      "blockedReason": null | "membership_inactive" | "store_locked"
                            | "store_archived" | "payment_lapsed",
      "paidThroughDate": null | "YYYY-MM-DD",
      "trialEndsAt": null | "YYYY-MM-DD",
      "subscriptionState": "ACTIVE" | "TRIAL" | "TRIAL_ENDING"
                         | "SUBSCRIPTION_ENDING" | "RESTRICTED",
      "allowedOutlets": [
        {
          "id": "<outletId>",
          "outletCode": "OBLRCHN01",
          "displayName": "Chinnapanahalli",
          "isDefault": true,
          "status": "ACTIVE" | "CLOSED" | "RELOCATED"
        }
      ],
      "defaultOutletId": "<outletId>" | null
    }
  ]
}
```

Semantics from `resolveAllowedOutlets`
([session.ts:574-620](../../laundry_pos/src/server/auth/session.ts)):

- **OWNER** — every `ACTIVE` outlet of the organization, oldest first;
  `isDefault` is simply "first in the list", not a real preference.
- **EMPLOYEE** — only outlets with an active `OutletMembership`,
  default first. **May be empty** — that employee cannot transact
  anywhere (see O4).

`allowedOutlets` never contains a non-`ACTIVE` outlet, so the app does
not need to filter by `status`. Keep the field; render nothing from it.

### Order shape

`Order` carries `outletId?: string`
([admin.types.ts:16](../../laundry_pos/src/features/admin/admin.types.ts))
and **no outlet display name**. Resolve the name locally from the
cached `allowedOutlets`. A missing/empty `outletId` means
**organization-wide** (a pre-outlet or org-level order) — label it
exactly `Organization-wide`, matching the workspace.

---

## O2 — Outlet scope: storage, state, transport

Three pieces, mirroring how `activeStoreId` already works.

### O2.1 `LocalCache` (`lib/core/storage/local_cache.dart`)

Add alongside `keyActiveStoreId` (line 48):

```dart
static const String keyAllowedOutlets   = 'allowed_outlets';   // per store
static const String keyActiveOutletId   = 'active_outlet_id';  // per store
static const String keyAllOutletsScope  = 'all_outlets_scope'; // bool, owner only
```

All three are **store-scoped** — reuse `_storeScopedKey` (line 178).

`activeOutletId == null` means one of two different things, so store the
boolean too:

- `allOutletsScope == true` → owner is viewing everything; send no
  outlet id.
- `allOutletsScope == false` → nothing selected yet; the app must ask
  before any outlet-scoped call.

**Extend the cache scoping.** `_storeScopedKey` currently keys on store
only, so switching outlets would serve the previous outlet's cached
orders and resume its sync cursor. Add an outlet-scoped variant and use
it for **`keyCachedOrders`, `keyLastSyncCursor`, and
`keyCachedDashboardMetrics`**:

```dart
String _outletScopedKey(String baseKey) =>
    '$baseKey::${getActiveStoreId() ?? 'none'}'
    '::${getActiveOutletId() ?? (isAllOutletsScope() ? 'all' : 'none')}';
```

Leave products, payment methods, staff and profile on the store-scoped
key — they are organization-wide, not per outlet.

### O2.2 `OutletScopeCubit` (`lib/features/shell/bloc/outlet_scope_cubit.dart`)

New, small, and the only writer of the three keys above.

```dart
class OutletScope {
  final List<Outlet> allowed;   // from login, cached
  final String? activeOutletId; // null when allOutlets or unset
  final bool allOutlets;        // owner-only
  final bool isOwner;
}
```

- `hydrate()` — read cache on start.
- `adoptFromLogin(organizations, activeStoreId)` — persist
  `allowedOutlets`; set the initial scope per O3.
- `select(outletId)` / `selectAllOutlets()` — persist, then emit. Every
  consumer (`OrdersBloc`, `OwnerBloc`, `CartBloc`, `SyncManager`) must
  **clear its loaded data and refetch** on a scope change; a stale list
  under a new outlet label is the bug this whole section prevents.
- `requiresSelection` — `true` when an employee has >1 allowed outlet
  and none is active, or when an owner has outlets but no scope yet.

### O2.3 Dio interceptor (`lib/core/network/dio_interceptors.dart`)

Beside the existing `X-Store-Id` block (lines 76-79):

```dart
if (!options.headers.containsKey('X-Outlet-Id')) {
  final outletId = _localCache.getActiveOutletId();
  if (outletId != null && outletId.isNotEmpty) {
    options.headers['X-Outlet-Id'] = outletId;
  }
}
```

Send **nothing** when the owner is in All-outlets scope — absence is
what means "whole organization". Never send an empty string.

`/api/v1/dashboard` additionally needs `?outletId=` built into the
request in the repository; the header alone will not scope it.

---

## O3 — Initial scope after sign-in

| Role | Allowed outlets | Initial scope |
| --- | --- | --- |
| OWNER | 0 | All outlets (the org has no outlets; everything is org-wide) |
| OWNER | ≥1 | **All outlets** |
| EMPLOYEE | 0 | Blocked — see O4 |
| EMPLOYEE | 1 | That outlet, silently |
| EMPLOYEE | ≥2 | Show the picker; block the shell until chosen |

The owner default matches the workspace, where "All outlets" is the
landing scope and a specific outlet is a deliberate narrowing.

---

## O4 — Employee with no outlet

An active employee assigned to zero outlets cannot read or create a
single order — every call 403s by design. The workspace surfaces this
as a warning badge on the Employees screen (defect D-44); mobile must
surface it to the person actually blocked.

Reuse `lib/shared/widgets/blocked_screen.dart`:

> **No outlet assigned**
> Your account isn't assigned to an outlet yet, so orders can't be
> loaded. Ask your store owner to assign you to one, then sign in again.

With a **Sign out** action. Do not render the bottom nav, the orders
list or New sale behind it.

---

## O5 — Screens and widgets

### O5.1 `OutletSwitcher` — new shared widget

`lib/shared/widgets/outlet_switcher.dart`. Model it on the existing
`lib/features/shell/presentation/store_switcher_dialog.dart`; do not
invent a second pattern.

- **Trigger**: a compact pill in the screen header showing the active
  outlet's `displayName`, or `All outlets`. 44px touch floor. Caret on
  the right, label left-aligned — the workspace shipped a bug where a
  `space-between` trigger centred its own label; don't repeat it.
- **Sheet**: one row per allowed outlet — `displayName` primary,
  `outletCode` secondary, check mark on the active one. Owners get an
  `All outlets` row pinned at the top **on Dashboard, Orders and
  Expenses only**. Employees never see it.
- **Hidden entirely** when `allowed.length <= 1` and the user is not an
  owner with an All-outlets option. One outlet is not a choice.

### O5.2 Dashboard (`owner_dashboard_screen.dart`)

- Mount `OutletSwitcher` in the header; pass `?outletId=` (not the
  header) to `/api/v1/dashboard`.
- **Vocabulary, to match the workspace's M0 standardisation:**
  - "Waiting" → **Open orders**, defined as *not yet Delivered*
    (`!isDelivered(status)`) — not "Pending status only". Today it reads
    as a status name; it is a backlog count. (line ~589)
  - "Completed" → **Delivered**, so the tile and the status pill use one
    word for one thing. (line ~599)
  - Income/Expenses chart → **Collected vs expenses — this month**,
    legend "Collected", subtitle "payments collected this month".
    "Income" reads as billed revenue; the figure is cash received.
    (line ~1087)
- Status donut legend keeps Pending / In progress / Ready / Delivered,
  but recolour Ready per O8.
- The period control (lines 690-730) is already correct — human labels
  and a reversed-range clamp at lines 91-97. **Leave it alone.**

### O5.3 Orders list (`orders_list_screen.dart`, `owner_orders_screen.dart`)

- `OutletSwitcher` in the header (owner: with All outlets).
- When the scope is All outlets **and** the org has >1 outlet, show the
  outlet name on each order row, resolved from the cached list;
  `Organization-wide` when `outletId` is null/empty. Hide the line
  entirely in a single-outlet scope — it is noise there.
- Do **not** add a client-side outlet filter on top of the switcher.
  The workspace has both and it caused defect D-39 (a "Clear" that left
  zero outlets selected and an empty table). One control, server-side.

### O5.4 New sale (`customer_details_screen.dart` → `checkout_screen.dart`)

- **Outlet is mandatory.** No org-wide orders from mobile. If the scope
  is All outlets when the flow starts, show an outlet step/sheet first
  and pin that outlet for the whole cart — do not let it change
  mid-cart.
- Persist the chosen `outletId` in `CartState` and include it in the
  create payload **and** in the queued offline action, so a cart
  created in one outlet and synced later still lands in the right one
  (bulk-sync rejects a mismatch against the header — see O1).
- Show the outlet name on the checkout summary, above the payment
  block, so what is being committed is visible.

### O5.5 Checkout payment methods — stop hardcoding

`checkout_screen.dart:237-262` hardcodes Cash / UPI / Pay-on-delivery
and `cart_bloc.dart:172-175` submits the literal strings `'Cash'` /
`'UPI'`. The app **already** fetches and caches the real list
(`pos_repository.dart:97-128`) and ignores it.

Replace with:

- One selectable row per method returned by `/api/v1/payment-methods`,
  labelled with the server's `name` and submitted as that exact `name`
  (the resolver matches on id, code or case-insensitive name —
  [platform-payment-methods.ts:201-232](../../laundry_pos/src/server/services/platform-payment-methods.ts)).
- **"Pay on delivery" stays**, but as a separate *no-payment* choice,
  not a method: it means "send no `initialPayment`", exactly as today.
  It must not be submitted as a method name — no such method exists
  server-side and it would be rejected.
- Empty list → disable prepaid options and show
  *"No payment methods are enabled. Ask the owner to enable one in
  Profile → Payment methods."* Do not silently fall back to "Cash".
- Keep the model tolerant: `active ?? enabled ?? true` (O0.A).
- **Nothing is pre-selected** (O0.5). "Place order" stays disabled until
  a payment option is tapped. There is no void, refund or correction
  path anywhere in the backend — a payment recorded by a wrong default
  can only be undone with direct database access. One tap is cheaper.
- Remove the **Add payment method** and **Rename** screens; the
  endpoints behind them are retired. Keep only enable/disable, via
  `PATCH /api/v1/payment-methods/{id}` with `{"enabled": bool}`.

### O5.6 Expenses (`expenses_screen.dart`, owner)

Send `X-Outlet-Id` with the scope; show the switcher. An expense
created in a specific scope is attributed to that outlet by the server
([expenses/route.ts:25](../../laundry_pos/src/app/api/v1/expenses/route.ts)).
In All-outlets scope the expense is org-wide — say so under the form
rather than letting it be a surprise.

---

## O6 — Offline sync

`SyncManager` / `SyncEngine` currently queue actions with no outlet.
Three required changes:

1. **Stamp every queued action with the `outletId` it was created
   under.** Do not resolve it at flush time — the scope may have
   changed by then.
2. **Group the flush by outlet.** As of 2026-09-26 the server honours
   each action's own `payload.outletId`, so an *owner* may mix outlets
   in one batch. An **employee** still may not — the route 403s the
   whole call if any `create_order` names a different outlet than the
   request
   ([bulk-sync/route.ts:26-31](../../laundry_pos/src/app/api/v1/orders/bulk-sync/route.ts)).
   One request per outlet is the pattern that is correct for both roles;
   use it.
3. **Delta sync is per outlet.** `GET /api/v1/orders/sync` filters by
   outlet, so the cursor is only meaningful within one scope — hence
   the outlet-scoped cursor key in O2.1. Switching scope must not
   resume the other scope's cursor.

A `403 FORBIDDEN` on flush means outlet access changed. Move the batch
to the dead-letter queue, clear the outlet selection, and route to
re-authentication (O0.3). Do not retry in a loop.

---

## O7 — Session and error handling

- `AuthRepository` (lines 46-67, 86-101) reads only `stores[]`. Parse
  `organizations[]` too and hand it to `OutletScopeCubit.adoptFromLogin`.
  Keep reading `stores[]` — nothing else depends on the new array.
- Cold start uses `/auth/status`, which since 2026-09-26 returns the same
  `organizations[].allowedOutlets` as login (O0.B). Cache them, then
  hydrate the scope; drop an active outlet that is no longer allowed and
  auto-select a sole remaining one. Only if nothing is cached at all
  (offline, older server) and a token exists, force a fresh sign-in rather
  than guessing an outlet.
- Centralise a reason-less `403 FORBIDDEN` (and a `400 "Invalid outlet."`)
  on an outlet-scoped call: re-read `/auth/status`. If the active outlet
  is **gone** from the fresh list, clear it and re-prompt (picker,
  auto-select, or the O4 blocked screen). If it is **still** listed, or
  the refresh fails, the denial is not about the outlet — sign out, as
  before. Re-prompting against a list that still contains the outlet
  would loop. Never present a 403 as "no orders".

---

## O8 — Status colours and phone, from the web fix round

### O8.1 `Ready` moves from amber to violet

`status_pill.dart` maps `PillVariant.ready` → `AppColors.warning`
(amber), which is the same amber as Unpaid / Part-paid / overdue. Work
status and payment status then look identical at a glance. The
workspace fixed this with `statusTone()`: **Pending grey, In Progress
blue, Ready violet, Delivered green**, leaving amber to payments alone.

Add to `app_colors.dart`, matching the workspace tokens exactly:

```dart
static const Color violet   = Color(0xFF6B3FC9);
static const Color violetBg = Color(0xFFF3EEFE);
```

Point `PillVariant.ready` at them, and update the dashboard donut
legend colour (line ~1446) to match. The other three already agree
with the web.

### O8.2 Phone normalisation on paste

`customer_details_screen.dart:85` rejects `+91 98765 43210` outright.
That is safer than the pre-fix web (which silently saved the *wrong*
number, `9198765432`) but still fails a perfectly normal paste.

Adopt the workspace's final behaviour: keep the raw text while typing,
normalise on blur and on submit, validate the normalised value.

```dart
String tenDigitPhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) return digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0'))  return digits.substring(1);
  return digits;
}
```

Anything that is not exactly 10 digits after normalisation keeps the
existing inline error. Do **not** truncate to 10 — truncation is the
bug that shipped on web.

---

## O9 — Explicitly out of scope

The rest of the workspace's M0–M9 round does not port: it was CSS
scoping, keyboard operability, native `<dialog>` behaviour, focus
order, 44px touch targets and horizontal-overflow work that Flutter and
`docs/DESIGN-SPEC.md` already handle. Specifically **not** to be done
here: D-05–D-21, D-26–D-30, D-38–D-47, D-49–D-52, M-01–M-11.

Also out of scope: an outlet **management** UI (create/rename/close
outlets) — that is Super Admin only and has no mobile API; and the
owner's per-outlet summary cards from the workspace dashboard, unless
asked for separately.

---

## O10 — Verification

Not "it compiles". Each item is a thing you observed.

1. `flutter analyze` clean; `flutter test` passes.
2. **Employee, one outlet** — sign in, orders list loads (this is the
   403 that is broken today), punch an order, confirm the server shows
   it against that outlet.
3. **Employee, two outlets** — picker appears at sign-in; switching
   outlets empties and refetches the list; no row from the other outlet
   survives the switch.
4. **Employee, zero outlets** — blocked screen, sign-out works, no
   order screens reachable.
5. **Owner** — lands on All outlets; dashboard totals equal the sum of
   the per-outlet scopes; narrowing to one outlet excludes org-wide
   orders; the orders list labels org-wide rows `Organization-wide`.
6. **Payment methods** — rename a method in the workspace, confirm the
   new name appears on mobile checkout and the order is accepted.
   Disable all methods, confirm the empty-state copy and that no order
   is submitted with a fabricated method.
7. **Offline** — queue orders in two different outlets while offline,
   reconnect, confirm two separate bulk-sync calls and both orders
   landing in the right outlet.
8. **Revocation** — remove the employee's outlet membership server-side
   while they are signed in; confirm the next call routes to
   re-authentication, not an empty list.
9. `Ready` renders violet, distinct from every amber payment pill.
10. Paste `+91 98765 43210` into the phone field — accepted, stored as
    `9876543210`.

---

## O11 — Suggested order of work

```
1. ~~O0.A backend payment-methods swap~~    DONE 2026-09-26, server side
2. O2 storage + cubit + interceptor         → verify: X-Outlet-Id on the wire in a request log
3. O7 login parsing + O3 initial scope      → verify: employee (1 outlet) orders list loads
4. O4 blocked screen                        → verify: zero-outlet employee cannot reach orders
5. O5.1 switcher + O5.3 orders              → verify: switching refetches, no stale rows
6. O5.4 + O5.5 new sale and payment methods → verify: order lands in the chosen outlet
7. O6 offline queue per outlet              → verify: two outlets, two bulk-sync calls
8. O5.2 dashboard scope + vocabulary        → verify: totals reconcile across scopes
9. O5.6 expenses scope                      → verify: expense attributed to the scope
10. O8 violet Ready + phone normalisation   → verify: paste test, colour check
```

Steps 2-4 alone fix the employee 403. Ship them before the rest if you
need the app working sooner.
