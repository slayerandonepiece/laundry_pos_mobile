# Web to mobile parity audit - 1 October 2026

Read-only audit. Web (source of truth): `../laundry_pos` working tree, branch `feat/expense-routes-and-hardening-2`, uncommitted. Mobile: this repo, branch `feat/expense-edit-and-switcher-fix`, uncommitted. Nothing was built, run or tested; every status is from reading code.

Path convention: web cites are relative to `../laundry_pos/` (prefix `W:`), mobile cites relative to this repo's `lib/` (prefix `M:`) unless stated. "Chain" = UI -> bloc/event -> repository -> API client call -> backend route that exists.

Status legend: Impl = Implemented (full chain traced); Part = Partial; Miss = Missing; Diff = Intentionally-different; NA = N-A-for-mobile. Blocker: none / BE (needs new backend API) / mobile-only. Offline: ON = needs connection; OFF-ok = works from cache/queue. Size S/M/L.

Input note: `../laundry_pos/audit/` (Codex's 199-bullet artifacts) does NOT exist in the web working tree (searched: `audit` dirs, `*audit*` to depth 2; only `scripts/qa_audit.mjs`). The only inputs actually available were WEB-MOBILE-FEATURE-GAPS.md, HANDOFF.md, MOBILE-API-CONTRACT.md and source. Capability bullets below were derived directly from web components.

---

## 1. Summary table (rows = capability bullets in section 2)

Counts are of the bullets I wrote from reading the web components against mobile code (not Codex's 199, which are not on disk). Impl = Implemented; Part = Partial; Miss = Missing; Diff = Intentionally-different (incl. mobile-only extras); Defect = mobile bug found in the audited area; NA = n/a or web-only; Other = cross-reference rows.

| Module | Impl | Part | Miss | Diff | Defect | NA/Other | Total |
|---|---|---|---|---|---|---|---|
| 1 Dashboard | 9 | 3 | 3 | 2 | 0 | 1 | 18 |
| 2 Owner orders | 10 | 1 | 0 | 1 | 0 | 0 | 12 |
| 3 Employee orders | 7 | 0 | 0 | 1 | 0 | 0 | 8 |
| 4 POS / new sale | 9 | 1 | 0 | 1 | 0 | 1 | 12 |
| 5 Order details | 9 | 0 | 1 | 2 | 0 | 0 | 12 |
| 6 Invoices | 4 | 0 | 2 | 3 | 0 | 0 | 9 |
| 7 Products | 4 | 2 | 2 | 1 | 0 | 0 | 9 |
| 8 Expenses | 10 | 1 | 0 | 1 | 3 | 0 | 15 |
| 9 Staff | 7 | 0 | 3 | 0 | 0 | 0 | 10 |
| 10 Outlets | 2 | 1 | 2 | 1 | 0 | 1 | 7 |
| 11 Profile | 3 | 2 | 4 | 0 | 0 | 0 | 9 |
| 12 Payment methods | 4 | 0 | 0 | 1 | 0 | 0 | 5 |
| 13 Subscription/access | 3 | 5 | 2 | 1 | 1 | 0 | 12 |
| 14 Announcements | 0 | 0 | 1 | 1 | 0 | 1 | 3 |
| 15 Auth/session | 8 | 1 | 1 | 0 | 0 | 0 | 10 |
| **Total** | **89** | **17** | **21** | **16** | **4** | **4** | **151** |

Caveat on "Impl": the full UI -> bloc -> repository -> API -> route chain was opened hop by hop for expenses, payment recording/status, staff, payment methods, profile, change-password, dashboard load, invoice fetch and bulk-sync. For pure read/list/filter rows (orders registers, products list, order detail display) I cite the screen and the repository sync call but did not open every widget line; treat those Impl rows as "chain cited, UI detail not line-verified" (see section 6).

Intentionally web-only (excluded from mobile scope): Super Admin console (stores, users, plans, billing, activity, payment-method catalogue, trial endpoints: W:src/app/super-admin/**, W:src/app/api/v1/super-admin/**), platform billing/invoices (W:src/app/super-admin/(shell)/subscriptions/**), announcement authoring (W:src/features/super-admin/actions/announcements.actions.ts), outlet provisioning/relocation (W:OutletsList.tsx:22), web `/sync/status` cache probe (W:api/v1/sync/status/route.ts), platform payment-method duplicates `/payment-methods/platform*` (deprecated), desktop-only chrome (sidebar, tables).

Web-only defects mobile must NOT copy:
1. Payment method preselected at checkout (W:OrderEditorContainer.tsx:31) - contract section 4.4 forbids; mobile starts unselected (M:checkout_screen.dart:26).
2. Server accepts 8-15 digit order phone (W:src/server/services/orders.ts:60) and profile phone 8-15 (W:profile.ts:30); the web UI itself checks 10 digits (OrderEditorContainer.tsx:68). Keep mobile `^[6-9]\d{9}$` (M:customer_details_screen.dart:43).
3. "Password last changed" from `user.updatedAt` (W:profile/page.tsx:35) - not a real timestamp.
4. "New password must differ" enforced only in web UI (W:Profile.tsx:60-64), not by the API.
5. Slab monotonicity enforced only in the web editor (W:ProductEditorContainer.tsx:33), not by the API (products.ts:7).
6. Orders page pushes the entire order list to the client and filters there (W:orders/page.tsx:29-31, OrderTable.tsx:241) - fine on web, do not mirror on mobile (use delta sync).
7. Contract doc claims every v1 response is `no-store`, but `GET /products` sends `private, max-age=30` (W:products/route.ts:15, handler.ts:138-139) - doc is stale, not a mobile issue.

---

## 2. Per-module detail

## Module 1 - Dashboard

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| D-01 | Today's sales + orders-today tiles | W:src/features/admin/components/Dashboard.tsx:90-91 | M:features/owner/presentation/owner_dashboard_screen.dart:536-610 (`_buildMoneyCards`); chain: LoadDashboardEvent -> owner_bloc.dart:16,70 -> owner_repository.dart:136 -> GET `ApiEndpoints.dashboard` -> W:src/app/api/v1/dashboard/route.ts:15 | Impl | none | OFF-ok (scope cache, owner_repository.dart:175-215) | - |
| D-02 | Period sales (mobile shows "this month") | W:Dashboard.tsx:90 (only today) + trend range | M:owner_dashboard_screen.dart:516-523 | Impl, with caveat: when `periodSales`==0 it shows `todaySales` (lines 517-523) so a true zero month is not distinguishable from missing data (open item D1.3 in the 27 Sep checklist still holds) | none | OFF-ok | S |
| D-03 | Open orders count | W:Dashboard.tsx:92 | M:owner_dashboard_screen.dart:632-640 (tile) -> drill-down `OrdersDrillDown.open` (`_openOrders`, line 411 region) | Impl | none | OFF-ok (drill-down uses cached orders) | - |
| D-04 | Expenses this month | W:Dashboard.tsx:93 | M:owner_dashboard_screen.dart:1316-1360 (inside "Collected vs expenses", from `metrics.cash`/`cashRange`); no standalone tile | Part (shown only as chart series, no headline figure) | none | OFF-ok | S |
| D-05 | Booked-sales trend (order-creation basis) | W:Dashboard.tsx:95; W:src/features/admin/admin.analytics.ts:119 (`bars`) | M:features/owner/data/models/dashboard_model.dart:75,116 (`bars` now retained); owner_dashboard_screen.dart:320 (`bars: dateCard.metrics?.bars`) -> `getPeriodMetrics` owner_repository.dart:244 | Impl (27 Sep gap D1 fixed; "Sales by date" now plots booked `bars`, with 7d/month/prev-month/custom filter) | none | ON for non-default period (owner_repository.dart:247-249 throws offline); default month cached | - |
| D-06 | Previous-period comparison series | W:Dashboard.tsx:95 (`previousPoints`), props :25 | not found (searched: `previousPoints`, `previous`, `comparison` in lib/features/owner) | Miss | none (can compute by second request with shifted from/to; route supports it, W:dashboard/route.ts:20-37) | ON | M |
| D-07 | Default "last 14 days" trend | W:Dashboard.tsx:25 (`trendTitle` default) | M uses month-to-date default, owner_repository.dart:115-130 (`_defaultRange`, `_isDefaultDashboardRequest`) | Diff (deliberate; do not change) | none | - | - |
| D-08 | Collected vs expenses (this month) + net badge | W:Dashboard.tsx:128-130, DashboardCharts.tsx `EarningsDonut` | M:owner_dashboard_screen.dart:1316-1360 (bar/net chart) | Impl | none | OFF-ok | - |
| D-09 | Order status breakdown | W: not a web tile (web shows Open orders only) | M:owner_dashboard_screen.dart:1541-1625 | Diff (mobile extra) | none | OFF-ok | - |
| D-10 | Sales by service mix | W:admin.analytics.ts (`serviceMix`), W:Dashboard.tsx has no donut (service data from rollups `type=services`, W:dashboard/rollups/route.ts:38) | M:owner_dashboard_screen.dart:1733-1800; dashboard_model.dart:113 | Impl | none | per-period ON | - |
| D-11 | Needs attention: overdue count + Due-today with action link | W:Dashboard.tsx:44-66 (`d.overdue`, `d.dueToday`); W:admin.analytics.ts:182-183 | M: Due today chip only, owner_dashboard_screen.dart:650-657 -> `OrdersDrillDown.dueToday`. `overdue` is parsed (dashboard_model.dart:67,111) but never rendered (searched: `metrics.overdue`, `Overdue`, `Needs attention`, `All caught` in owner_dashboard_screen.dart: no hits) | Part | none | OFF-ok | S |
| D-12 | Recent orders list (4 single-outlet / 3 all-outlet), outlet column in aggregate | W:Dashboard.tsx:67-86 | M:owner_dashboard_screen.dart:408-413, 1840-1960 (`_RecentOrdersCard`, outlet label via `_outletLabel` :1853, newest-first sort :1867, `take(_shown)` :1873) | Impl (27 Sep D3.2 done and verified in code) | none | OFF-ok (cached orders) | - |
| D-13 | Attention/tiles drill into filtered orders | W:Dashboard.tsx:50,58 (`/admin/sales?attention=1`) | M:owner_dashboard_screen.dart:630-657, orders_drill_down.dart | Impl | none | OFF-ok | - |
| D-14 | Per-outlet summary cards (sales today, orders, open, share-of-best bar, vs-yesterday %) in all-outlets scope | W:Dashboard.tsx:99-127 (data: W:src/server/services/dashboard-rollups.ts via W:src/app/api/v1/dashboard/rollups/route.ts) | not found (searched: `rollups`, `perOutlet`, `outletCards`, `dashboard/rollups` across lib; `ApiEndpoints` has no rollups entry, api_endpoints.dart:63-64) | Miss | none - the web route already exists and allows OWNER with optional outlet (rollups/route.ts:34-37) | ON (not cached) | M |
| D-15 | Outlet detail link from card ("View detail") | W:Dashboard.tsx:126 | not found (see Outlets module) | Miss | BE (`/api/v1/outlets/{id}`) | ON | L |
| D-16 | All-outlets vs single-outlet scope | W:DashboardOutletControl.tsx | M:features/shell/bloc/outlet_scope_cubit.dart, owner_repository.dart:186 (`outletId` query) | Impl | none | OFF-ok per-scope cache (`setCachedDashboardMetricsForScope`) | - |
| D-17 | Empty state ("No orders yet" / first-use) | W:Dashboard.tsx:82-85 | M:owner_dashboard_screen.dart:949 (`emptyText`) for charts; no first-use dashboard empty state found (searched: `No orders yet`, `EmptyState` in owner_dashboard_screen.dart) | Part | none | OFF-ok | S |
| D-18 | Dashboard-specific restricted/locked read behavior | W:dashboard rollups `allowRestricted: true` (rollups/route.ts:16); main route does not (dashboard/route.ts:17) | mobile routes to BlockedScreen on any block | see Subscription module | - | - | - |


## Module 2 - Owner orders

Server note: web pages read orders with `allowLockedReadOnly: true` (W:src/app/(workspace)/admin/orders/page.tsx:21); the v1 list/sync routes use `allowRestricted: true` (W:src/app/api/v1/orders/route.ts:15, orders/sync/route.ts:20).

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| OO-01 | Register of all orders, newest first, org-wide for owner | W:orders/page.tsx:29 (`listOrders(storeId)` for OWNER); OrderTable.tsx:207 | M:features/owner/presentation/owner_orders_screen.dart:298-420; chain: orders_bloc -> orders_repository.dart `syncOrdersDelta` :945/:955 -> GET `ordersSync` (:995) -> W:orders/sync/route.ts:20 | Impl | none | OFF-ok (cached + delta sync) | - |
| OO-02 | Search by customer / phone / order code | W:OrderTable.tsx:256-262,368 | M:owner_orders_screen.dart:457 (hint), :475 clear | Impl | none | OFF-ok | - |
| OO-03 | Work-status filter (All/Pending/In progress/Ready/Delivered) | W:OrderTable.tsx:223-229 | M:owner_orders_screen.dart:495-523 (work dropdown) | Impl | none | OFF-ok | - |
| OO-04 | Payment-status filter (Unpaid/Part-paid/Paid) | W:Sales.tsx:25 | M:owner_orders_screen.dart:522-523 | Impl | none | OFF-ok | - |
| OO-05 | Date range (from/to) filter | W:OrderTable.tsx:211-212,253 | M:owner_orders_screen.dart:45 (period tied to Sales summary card), :383 ("Selected dates" chip) | Impl | none | OFF-ok | - |
| OO-06 | Due today / Late shortcuts that ignore the date range | W:Sales.tsx:21 (`delivery` today/late) | M:owner_orders_screen.dart:393,401,196-197 | Impl (semantics vs web not byte-verified - see Not verified) | none | OFF-ok | - |
| OO-07 | Per-outlet multi-select filter incl. "Organization-wide" | W:OrderTable.tsx:207-210,246-251 | M: scope switcher `OutletTitleSwitcher(showAllOutletsOption: true)` owner_orders_screen.dart:306-308; no "Organization-wide" (null-outlet) bucket (searched: `Organization-wide`, `org-wide` in lib: no hit) | Part / Diff (single scope switch instead of multi-select; null-outlet orders only visible under All outlets) | none | OFF-ok | S |
| OO-08 | Sales/collected/balance summary | no equivalent card on W register (W has Dashboard) | M:owner_orders_screen.dart:555-700 | Diff (mobile extra) | none | OFF-ok | - |
| OO-09 | Outlet label on rows in aggregate view | W:OrderTable.tsx (outlets prop, Sales.tsx:15) | M:owner_orders_screen.dart:791-799,888 | Impl | none | OFF-ok | - |
| OO-10 | Cancelled legacy orders excluded | W:src/server/services/orders.ts (listOrders excludes; `legacyCancelled` flag used W:OrderPaymentSummary.tsx:60) | M: tombstones removed in orders_repository.dart (delta `deleted`, per 27 Sep O4) | Impl (not re-traced this session beyond the delta path) | none | OFF-ok | - |
| OO-11 | Empty / no-match states with Clear filters | W:Sales.tsx:34-42 | M:owner_orders_screen.dart:869 | Impl | none | OFF-ok | - |
| OO-12 | New sale entry with owner outlet pick | W:OrderEditorContainer.tsx:53,65,92 | M:owner_orders_screen.dart:160-180 (sheet to choose outlet when All-outlets and >1) -> `ResetSaleEvent(outletId)` | Impl | none | OFF-ok | - |

## Module 3 - Employee orders

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| EO-01 | Register limited to employee's selected outlet (never silent default) | W:orders/page.tsx:30 (`outletSelection.outletId`), W:api/v1/orders/route.ts:32-37 (403 without outlet) | M: sends X-Outlet-Id from scope; outlet_scope_cubit.dart; features/shell/presentation/outlet_required_screen.dart | Impl | none | OFF-ok | - |
| EO-02 | Search order/customer/phone | W:Sales.tsx:23 | M:features/orders/presentation/orders_list_screen.dart:354 | Impl | none | OFF-ok | - |
| EO-03 | Work-status filter | W:Sales.tsx:24 | M:orders_list_screen.dart:409-439 (chips with counts) | Impl | none | OFF-ok | - |
| EO-04 | Payment-status filter | W:Sales.tsx:25 | M:orders_list_screen.dart:465 (dropdown); orders_state.dart:111-124 | Impl (27 Sep O1.1 done) | none | OFF-ok | - |
| EO-05 | Delivery filter (Selected dates / Due today / Late) | W:Sales.tsx:21 | M: `dueFilter` in orders_state.dart:133; dropdown in orders_list_screen.dart:~465-480 (labels not individually read) | Impl | none | OFF-ok | - |
| EO-06 | "To collect" quick chip | not a web control (web uses payment filter) | M:orders_list_screen.dart:415 | Diff (mobile extra) | none | OFF-ok | - |
| EO-07 | No owner financial summary shown to employee | W:api/v1/dashboard/route.ts:15 OWNER-only; rollups strips `expensesAmount` for EMPLOYEE (rollups/route.ts:56-62) | M: employee screen (orders_list_screen.dart:222-253) shows counts only (Total/Pending/In progress/Completed) | Impl | none | - | - |
| EO-08 | Employee with zero outlets blocked with explanation | W: no UI (server 403, orders/route.ts:36) | M:features/shell/presentation/outlet_required_screen.dart | Impl | none | - | - |

## Module 4 - POS / new sale

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| POS-01 | Browse/search services, add piece and weight items | W:ServiceGrid.tsx, OrderCart.tsx, QuantityForm.tsx | M:features/pos/presentation/new_sale_browse_screen.dart; dialogs/weighted_item_dialog.dart, edit_item_dialog.dart; cart_bloc.dart | Impl | none | OFF-ok (products cached, pos_repository.dart:72) | - |
| POS-02 | Slab pricing for weight items (limit/price + extra-kg rate) | W:OrderEditorContainer.tsx:122; W:src/server/pricing.ts | M:features/pos/data/models/product_model.dart:1-8 (`PricingSlab`); server recomputes on create (not re-traced) | Impl (client side display); server authority not re-verified | none | OFF-ok | - |
| POS-03 | Customer phone (10 digit) + name, returning-customer lookup | W:OrderEditorContainer.tsx:64-72; W:api/v1/orders/customer-lookup/route.ts | M:customer_details_screen.dart:43 (`^[6-9]\d{9}$`), :126-128 -> orders_repository.dart:154-159 -> GET `customerLookup` | Impl (mobile stricter than web: web regex `^[0-9]{10}$` at OrderEditorContainer.tsx:68; server accepts 8-15 digits, orders.ts:60 - web-only defect) | none | lookup ON, falls back silently offline (customer_details_screen.dart:126) | - |
| POS-04 | Expected delivery date (default +2 days, min today) | W:OrderEditorContainer.tsx:129 | M:checkout_screen.dart:48-51 (`showDatePicker`; HANDOFF says default today and past dates rejected - rejection not re-read) | Impl / Diff (default differs, deliberate) | none | OFF-ok | - |
| POS-05 | Order notes | W:OrderEditorContainer.tsx:143 | M:checkout_screen.dart:411-415; cart_bloc.dart:195-226 | Impl | none | OFF-ok | - |
| POS-06 | Payment method choice from enabled org methods; empty-list handling; no preselect | W:OrderEditorContainer.tsx:131-141 (preselects `paymentMethods[0]`, :31 - web-only defect, contract 4.4) | M:checkout_screen.dart:26,117-120,370 (explicit message, `_selectedMethodId` starts null) | Impl (stricter than web) | none | OFF-ok (methods cached) | - |
| POS-07 | Pay on delivery (no initialPayment) | W:payment-methods.ts (`isCashOnDelivery`), OrderEditorContainer.tsx:130 | M:cart_bloc.dart:240 (`paymentChoice != 'delivery'`), checkout_screen.dart:437 | Impl | none | OFF-ok | - |
| POS-08 | Partial "Received now" amount at creation (0 .. total) | W:OrderEditorContainer.tsx:60,77-78,131-137 | M: `initialPayment = {'amount': state.totalAmount ...}` only full amount, cart_bloc.dart:239-251; no partial field (searched: `advance`, `partial`, `receivedAmount` in checkout_screen.dart, cart_*.dart) | Part (partial can be recorded after creation via RecordPaymentEvent, orders_bloc.dart:39) | none (API accepts any amount: W:orders.ts createOrder initialPayment) | OFF-ok | S |
| POS-09 | Owner picks outlet (multi-outlet); employee uses own | W:OrderEditorContainer.tsx:53,65 | M:owner_orders_screen.dart:160-180; cart_bloc.dart:264,292 | Impl | none | OFF-ok | - |
| POS-10 | Idempotent create (key per cart, reused on retry); offline queue | W:OrderEditorContainer.tsx:50,82 (`crypto.randomUUID`) | M:cart_bloc.dart:257,270,289; pos_repository.dart:167 `createOrderOptimistic` -> orders_repository.dart:1235 queue -> bulk-sync :630 -> W:orders/bulk-sync/route.ts | Impl (mobile adds `offlineId`, contract 3.5) | none | OFF-ok | - |
| POS-11 | Category vocabulary on products (see Products) | - | - | see Module 6 | - | - | - |
| POS-12 | Block sale when subscription RESTRICTED / locked | W: web pages open with locked-read-only and disable mutations (orders/page.tsx:21; `readOnly` prop OrderDetails.tsx:13) | M: BlockedScreen replaces whole app (see Module 13) | Diff / Miss (see Module 13) | BE+mobile | - | L |

## Module 5 - Order details

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| OD-01 | Customer, delivery date, "Overdue/Due today/Upcoming" commitment, 4-step progress | W:OrderDeliveryDetails.tsx:13-38 | M:features/orders/presentation/order_detail_screen.dart:792 (stages list), detail body | Impl (progress UI); "Overdue" wording not individually confirmed | none | OFF-ok | - |
| OD-02 | Itemised bill: qty, rate ("/pc" or "Slab pricing"), amount | W:OrderPaymentSummary.tsx:61-66 | M:order_detail_screen.dart (items card); mobile PDF builder shows Rate column, order_pdf_builder.dart | Impl (screen vs PDF rate column not both read) | none | OFF-ok | - |
| OD-03 | Total / received / balance + paid state | W:OrderPaymentSummary.tsx:58,67 | M:order_detail_screen.dart:374 ("Balance due"), :401 ("Paid in full") | Impl | none | OFF-ok | - |
| OD-04 | Payments received list | W:OrderPaymentSummary.tsx:68 | M:order_detail_screen.dart (payments section; cites `order.payments`) | Impl | none | OFF-ok | - |
| OD-05 | Record partial/full payment (any amount <= balance, any status) | W:OrderPaymentSummary.tsx:6-58 | M:dialogs/record_payment_dialog.dart:305 -> orders_bloc.dart:294 -> orders_repository.dart:290 -> queue `record_payment` :308 -> bulk-sync -> W:orders/bulk-sync/route.ts (+ per-order route W:orders/[orderCode]/payments/route.ts:17 unused by mobile) | Impl | none | OFF-ok (queued, own `clientActionId`) | - |
| OD-06 | Update work status with confirm; "deliver anyway" when balance due | W:OrderTable.tsx:281-291 | M:dialogs/status_dialog.dart -> orders_bloc -> orders_repository.dart:253 -> `update_status` :264 | Impl | none | OFF-ok | - |
| OD-07 | Collect-and-deliver shortcut | not on web | M:order_detail_screen.dart:481, dialogs/collect_payment_dialog.dart | Diff (mobile extra) | none | OFF-ok | - |
| OD-08 | Status history (who/when) | W:OrderDetails.tsx:40-47 | M:order_activity_screen.dart:138-170 | Impl | none | OFF-ok | - |
| OD-09 | Care notes | W:OrderDetails.tsx:49 | M:order_detail_screen.dart:446; order_activity_screen.dart:107 | Impl | none | OFF-ok | - |
| OD-10 | Read-only detail when workspace is locked | W:OrderDetails.tsx:13 (`readOnly`), :56 (select disabled) | not found (searched: `readOnly`, `locked`, `isLocked` in features/orders/presentation) | Miss | BE (see Module 13) | - | M |
| OD-11 | Payment/status actions blocked server-side when store not writable | W:orders/[orderCode]/status/route.ts:16 and payments/route.ts:17 use plain `requireApiStoreSession` (no allowRestricted) | M: mobile handles 403 reasons -> BlockedScreen | Impl (server enforces) | none | queued actions retained? see Not verified | - |
| OD-12 | Notify customer on Ready (WhatsApp prompt) | not on web | M:order_detail_screen.dart:70-89 | Diff (mobile extra) | none | OFF-ok | - |

## Module 6 - Invoices

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| INV-01 | Invoice allocation only when paid in full and Delivered | W:api/v1/orders/[orderCode]/invoice/route.ts:23-27 (`assertStoreWritable`), W:src/server/services/order-invoices.ts:100-109 (paid-in-full + delivered check) | M:orders_repository.dart:361-376 (`getOrCreateInvoice`->GET `orderInvoice`), ready-bill flow dialogs/ready_bill_actions_sheet.dart | Impl | none | server allocation ON; retry queue `retryMissingInvoices` orders_repository.dart:403 | - |
| INV-02 | View invoice PDF | W:OrderInvoicePdfViewer.tsx:44 (server PDF via `/admin/orders/{code}/invoice/pdf`) | M:invoice_viewer_screen.dart + local builder order_pdf_builder.dart; server PDF `getInvoicePdfBytes` orders_repository.dart:486 exists but unused by UI (searched: callers) | Diff (local PDF by design) | none | OFF-ok | - |
| INV-03 | Print | W:OrderInvoicePdfViewer.tsx:35 | M:invoice_actions_sheet.dart:187-193, :321-325 (`Printing.layoutPdf`) | Impl | none | OFF-ok | - |
| INV-04 | Share PDF file | W:OrderInvoicePdfViewer.tsx:36 (shares link) | M:invoice_actions_sheet.dart:164-171, :299-310 (SharePlus file attachment) | Diff (file vs link) | none | OFF-ok | - |
| INV-05 | WhatsApp send | W:OrderInvoicePdfViewer.tsx:37 (wa link to public `/i/{token}/view`) | M:invoice_actions_sheet.dart:137-147 (OS share sheet with PDF); also order_detail_screen.dart:679 | Diff (file via share sheet) | none | OFF-ok | - |
| INV-06 | Public tokenized link (open in browser / download) | W:OrderInvoicePdfViewer.tsx:38-39; W:src/app/i/[token]/route.tsx, i/[token]/view/page.tsx | M:order_model.dart:101,125 parses `accessToken` but nothing builds `/i/{token}` (searched: `/i/`, `accessToken`, `launchUrl` in lib: only the model) | Miss | none (token already in Order DTO, contract 5) | ON | S |
| INV-07 | Invoice PDF matches web layout (dates, rate column, payments table, footer) | W:src/features/admin/pdf/OrderInvoicePdf.tsx | M:order_pdf_builder.dart (rebuilt 28 Sep); `generatedAt` consumed from DTO | Impl (visual equivalence not verified) | none | OFF-ok | - |
| INV-08 | Employee cannot fetch other outlet's invoice | W:order-invoices.ts:76-88 `assertCanReadOrderInvoice`, applied W:api/v1/orders/[orderCode]/invoice/pdf/route.tsx:16 and W:(workspace)/admin/orders/[orderCode]/invoice/pdf/route.tsx:24; JSON route :16-19 | M: not applicable (mobile does not call the PDF route) | Impl on web (the 28 Sep security gap is closed in code) | none | - | - |
| INV-09 | Restricted subscription may read existing invoice | W:invoice/route.ts:11,26 comment "Restricted subscriptions may still read an existing invoice" | M: BlockedScreen prevents reaching it | Miss (see Module 13) | mobile | - | M |

## Module 7 - Products / services

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| PR-01 | List + search by name/category | W:Catalogue.tsx:61-66 | M:features/owner/presentation/services_screen.dart:78 (filter), :207 (hint); products cached via pos_repository.dart:72 -> GET `products` -> W:api/v1/products/route.ts:9 | Impl | none | OFF-ok (read) | - |
| PR-02 | Add / edit service (item and weight types) | W:ProductEditorContainer.tsx:28-40; actions W:src/features/admin/actions/products.actions.ts | M:services_screen.dart:740-800 -> `OwnerRepository.createProduct/updateProduct` (owner_repository.dart:1798-1860, called directly from the widget at services_screen.dart:788,799; no bloc/event) -> POST `products` -> W:products/route.ts:17 (OWNER upsert) | Impl for online path; NOT queued offline (see PR-06) | none | ON | - |
| PR-03 | Active / inactive toggle | W:Catalogue.tsx:111-112 | M:services_screen.dart:970-997 (switch inside editor; `active` sent in body :1809-1818) | Impl | none | ON | - |
| PR-04 | Slab validation: limits strictly increasing, prices positive | W:ProductEditorContainer.tsx:33-35 (client only); server `slabSchema` only checks `limit>0`, `price>=0` (W:src/server/services/products.ts:7) | M:services_screen.dart:752-767 drops empty/zero tiers and silently sorts by limit; no duplicate/non-increasing rejection (searched: `increase`, `Slab limits` in services_screen.dart: none) | Part (looser than web; mobile can save duplicate limits) | none (could be server-side too, web-defect: server does not validate monotonic) | - | S |
| PR-05 | Category choices Laundry / Dry cleaning / Ironing / Home fabrics / Add-on | W:ProductEditorContainer.tsx:76 | M:services_screen.dart:823-840 (own vocabulary; preserves existing category) | Diff (decision pending; data is free-form string both sides, products.ts:12) | none | - | S |
| PR-06 | Offline product writes | W: n/a | none: product save refuses/fails offline (search: `enqueueOwnerAction` types in owner_repository.dart do not include product) | Part (acceptable; documented) | none | ON | M if wanted |
| PR-07 | "Confirm unit" legacy product guidance | W:Catalogue.tsx:19,44,111-112 (`needsUnit`) | not found (searched: `needsUnit`, `Confirm unit`, `legacy` in lib); product_model.dart defaults missing `type` to item (HANDOFF/27 Sep P2) | Miss (low value unless legacy rows exist) | none | - | S |
| PR-08 | Extra per-kg price after final slab | W:ProductEditorContainer.tsx:158 | M:services_screen.dart:769-771 (`_extraController`) | Impl | none | ON | - |
| PR-09 | Read-only catalogue when locked | W:Catalogue.tsx:56 (`readOnly` hides Add) | not found | Miss (see Module 13) | BE+mobile | - | M |

## Module 8 - Expenses

Backend routes verified present in the working tree: `GET/POST /expenses` (W:src/app/api/v1/expenses/route.ts:11,24), `PUT/DELETE /expenses/{id}` (W:src/app/api/v1/expenses/[id]/route.ts:7,18 - untracked file, i.e. not yet committed), `POST /expenses/{id}/pay` with optional `paidDate` (W:src/app/api/v1/expenses/[id]/pay/route.ts:13). All OWNER-only (`requireApiStoreSession(req,'OWNER')`).

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| EX-01 | List expenses, outlet scope | W:Expenses.tsx:30-34, 36-50 | M:features/owner/presentation/expenses_screen.dart; owner_repository.dart:362 GET `expenses` (+ per-scope cache :307-325) | Impl | none | OFF-ok | - |
| EX-02 | Create expense (title, category, amount, due, monthly, outlet) | W:ExpenseEditor.tsx:29-37; W:actions/expenses.actions.ts:11 | M:expenses_screen.dart:907-960 (form incl. `_monthly`, `_selectedOutletId`) -> `AddExpenseEvent` -> owner_bloc -> owner_repository.dart:500 `createExpense` POST `expenses` (or `_createExpenseOffline` :447 queue) -> W:expenses/route.ts:24 (idempotencyKey) | Impl | none | OFF-ok (queued with LOCAL id) | - |
| EX-03 | Explicit organization-wide vs outlet attribution on create | W:ExpenseEditor.tsx:29-37 | M:expenses_screen.dart:1111 ("Organization-wide"), :958-959 (`outletId`, `orgWide: _selectedOutletId == null`); owner_repository.dart:430-438 header/body handling | Impl (27 Sep E3 done) | none | OFF-ok | - |
| EX-04 | Outlet model retained end to end | W:Expense DTO | M:expense_model.dart:3,14,29,43 (`outletId`, `seriesId`) | Impl | none | - | - |
| EX-05 | Show attribution in list + details | W:Expenses.tsx:96-137, ExpenseDetails.tsx | M:expenses_screen.dart:746-754; expense_detail_screen.dart:117-126 | Impl (outlet unknown -> falls back to raw id, expense_detail_screen.dart:124 / expenses_screen.dart:754) | none | OFF-ok | - |
| EX-06 | Expense detail screen | W:ExpenseDetails.tsx (15 lines) | M:features/owner/presentation/expense_detail_screen.dart (new, untracked) opened from expenses_screen.dart:303 | Impl | none | OFF-ok | - |
| EX-07 | Edit expense (title/category/amount/due/outlet); recurring stays in its month | W:ExpenseEditor.tsx; actions W:expenses.actions.ts:29 | M:edit_expense_screen.dart:97-127 (`UpdateExpenseEvent`) -> owner_bloc.dart `_onUpdateExpense` -> owner_repository.dart:566-604 `updateExpense` -> PUT `expenseById` (api_endpoints.dart:50) -> W:expenses/[id]/route.ts:7; month clamp edit_expense_screen.dart:64-70 mirrors server rule | Impl (chain complete; real route exists but untracked) | none | ON: refuses offline (owner_repository.dart:583-585); buttons disabled offline expense_detail_screen.dart:250 | - |
| EX-08 | Delete expense (confirm; recurring stops series) | W:DeleteExpenseDialog.tsx:9-13; actions W:expenses.actions.ts:38 | M:expense_detail_screen.dart:89-110 -> `DeleteExpenseEvent` -> owner_repository.dart:606-624 -> DELETE `expenseById` -> W:expenses/[id]/route.ts:18 | Impl | none | ON (disabled offline :261) | - |
| EX-09 | Mark paid with chosen paid date (not future) | W:MarkExpensePaidDialog.tsx:8-26 (max today) | M:expense_detail_screen.dart:42-62 (picker, today max, 1 year min), also expenses_screen.dart:274,924 -> `MarkExpensePaidEvent(paidDate)` -> owner_repository.dart:676-711 -> POST `markExpensePaid` body `paidDate` (:626-640) -> W:expenses/[id]/pay/route.ts:13 | Impl | none | OFF-ok: queued `mark_expense_paid` carries `paidDate` (owner_repository.dart:660-670) and replay resolves LOCAL ids and passes it (:1555-1562) | - |
| EX-10 | Recurring ("monthly") flag and series semantics | W:ExpenseEditor.tsx:28; server W:expenses.ts | M:expenses_screen.dart:1138-1151, filter :400,:689; edit month clamp | Impl | none | OFF-ok on create | - |
| EX-11 | Period / unpaid / recurring / search filters + summary cards | web has only outlet pills (Expenses.tsx:36-50) | M:expenses_screen.dart:547-689 | Diff (mobile richer) | none | OFF-ok | - |
| EX-12 | Web delete wording for paid expenses ("removed from paid totals") | W:DeleteExpenseDialog.tsx:13 | not in mobile confirm text (expense_detail_screen.dart:90-93) | Part (copy only) | none | - | S |
| EX-13 | Edit/delete on an unsynced offline-created expense (id `LOCAL-...`) | n/a | NOT guarded: buttons enabled when online for ids starting `LOCAL-` (no `LOCAL-` check in expense_detail_screen.dart / edit_expense_screen.dart; id minted owner_repository.dart:459) -> PUT/DELETE `/expenses/LOCAL-...` would 404 | Defect (mobile-only) | mobile-only | - | S |
| EX-14 | Cache coherence after edit/delete across scopes | n/a | updateExpense/deleteExpense patch only the current scope's cache (owner_repository.dart:590-604, 614-624); other scopes (All outlets, other outlet) stay stale until their next sync; an outlet change moves the expense between scopes | Defect risk (mobile-only) | mobile-only | OFF-ok | S |
| EX-15 | Detail screen after failed edit | n/a | edit screen pops with locally built `updated` immediately after dispatch (edit_expense_screen.dart:97-127) and detail sets `_expense = updated` (expense_detail_screen.dart:82-86); on API failure the bloc emits error but `state.expenses` is unchanged so the BlocListener (:131) never reverts it | Defect risk (mobile-only) | mobile-only | - | S |

## Module 9 - Staff

Server facts: `GET/POST /employees` (W:src/app/api/v1/employees/route.ts), `PUT /employees/{id}` (W:src/app/api/v1/employees/[id]/route.ts:7, OWNER), `POST /employees/{id}/toggle-active` (kept for old queued items). `PUT` with `password` sets `mustChangePassword`, bumps `credentialVersion` and revokes all that user's sessions (W:src/server/services/employees.ts:215-247,282), i.e. the same semantics as web's dedicated reset (W:employees.ts:330-342). Outlet ids validated by `assertAssignableOutlets` (W:employees.ts:71, called :128 and :206).

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| ST-01 | List + search staff | W:Employees.tsx:18; search prop | M:features/owner/presentation/staff_screen.dart:215-241 (hint "Search name or phone...") ; owner_repository.dart:743 GET `employees` (+cache) | Impl | none | OFF-ok (cached; `GET /employees` now uncached server side per HANDOFF) | - |
| ST-02 | Add employee (name, phone, temp password >= 8, outlets, default) | W:EmployeeEditor.tsx:44-60,93-127 | M:staff_screen.dart:491-545 (name/phone/password>=8 check :514-521, outlets+default via `OutletAssignmentField` :625, :541-542) -> owner_repository.dart:792 POST `employees` | Impl | none | ON (`'Adding staff needs an internet connection'`, owner_repository.dart:838) | - |
| ST-03 | Edit name / phone | W:EmployeeEditor.tsx:44-49 | M:staff_screen.dart (`_EditStaff...` at :672) -> `_updateStaffDirect` -> PUT `employeeDetail` (owner_repository.dart:860/983) | Impl | none | OFF-ok (queued `update_staff`, replay :1635-1650) | - |
| ST-04 | Edit outlet assignments + default (sent only when changed) | W:EmployeeEditor.tsx:17-18,93-127 | M:staff_screen.dart:672-700; staff_model.dart:27,41,58; replay `_stringList(payload['outlets'])` owner_repository.dart:1645 | Impl (27 Sep S1.1-S1.3 verified in code) | none | OFF-ok | - |
| ST-05 | Assigned / default outlet badges; "No outlet assigned" warning | W:Employees.tsx:19,67-77,89-92 | M:staff_screen.dart:382-460 (`hasNoOutletAccess`, "No outlet access - assign one") | Impl | none | OFF-ok | - |
| ST-06 | Activate / deactivate | W:Employees.tsx:107-110 | M:owner_bloc.dart:474-480 -> owner_repository.dart:921 `toggleStaffActive` -> `_setStaffActiveDirect` PUT `{active}` :856-863 (idempotent) / queued `set_staff_active` replay :1607 | Impl (legacy `toggle_staff_active` replay at :1628 still present for pre-upgrade queue items; it is a non-idempotent toggle - risk is limited to such stale items) | none | OFF-ok | - |
| ST-07 | Owner resets employee password (temporary; ends sessions; forces change) | W:ResetEmployeePasswordDialog.tsx:6-23; action W:actions/employees.actions.ts:95; service W:employees.ts:330-342 | not found in mobile (searched `Reset`, `password` in staff_screen.dart: only the add-form password; `ForgotPasswordDialog` in features/auth is a different flow) | Miss | none - existing `PUT /employees/{id}` with `password` already does it (employees.ts:215-247,282); a dedicated route is optional | ON by design (never queue raw passwords) | M |
| ST-08 | Edit-employee optional new temporary password | W:EmployeeEditor.tsx:54-61 ("Leave blank to keep current") | not found | Miss (same as ST-07; one UI can serve both) | none | ON | S (with ST-07) |
| ST-09 | Employee outlet grants limit what they see after refresh | W:session.ts:574 `resolveAllowedOutlets` | M:outlet_scope_cubit.dart:226 (access lost -> drop selection), test/features/outlet_access_lost_test.dart | Impl (device pass still pending per HANDOFF) | none | - | - |
| ST-10 | Read-only staff when locked | W:Employees.tsx:7,18,78 (`readOnly`) | not found | Miss (Module 13) | BE+mobile | - | M |

## Module 10 - Outlets (directory / detail)

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| OU-01 | Outlet scope selection (single / all / default) | W:StoreSwitcher.tsx, DashboardOutletControl.tsx | M:features/shell/bloc/outlet_scope_cubit.dart:9,56; shared/widgets/outlet_title_switcher.dart; shell/presentation/store_switcher_dialog.dart | Impl | none | OFF-ok | - |
| OU-02 | Employee with no outlet / revoked outlet handled | server 403 (W:orders/route.ts:36) | M:shell/presentation/outlet_required_screen.dart; outlet_scope_cubit.dart:42,226 | Impl | none | - | - |
| OU-03 | Owner outlet directory: name, code, status (Active/Relocated/Closed), opened date, address | W:OutletsList.tsx:9-17,40+ (data via server component W:src/app/(workspace)/admin/outlets/page.tsx -> `listOutletsForStoreAdmin`) | not found (searched `directory`, `OutletsList`, `/outlets` in lib; `ApiEndpoints` has no outlets route; model only id/code/name/isDefault/status, outlet_model.dart:1-40). v1 API exposes only ACTIVE `allowedOutlets` (contract section 2) | Miss | BE: needs `GET /api/v1/outlets` (all statuses + address/opened date) | ON | M |
| OU-04 | Outlet detail: today snapshot, month collected vs expenses, 14-day trend, employees at outlet, contact, order status today | W:OutletDetail.tsx:148-214; page W:(workspace)/admin/outlets/[outletId]/page.tsx:20-35 | partial equivalents only via single-outlet dashboard scope (D-16) - sales/expense charts exist; no address/contact/opened date/employees-per-outlet (searched `Contact & details`, `Employees at this outlet`) | Part | BE for facts (`GET /api/v1/outlets/{id}`); analytics needs none | ON for facts | L |
| OU-05 | Closed/relocated outlet history readable | W:OutletDetail.tsx:85-87 | not possible: allowedOutlets never contains non-ACTIVE (contract section 2) | Miss | BE (same endpoint) | ON | S (after OU-03) |
| OU-06 | Outlets provisioned by support only (no owner provisioning) | W:OutletsList.tsx:22 info banner | none (do not build) | Intentionally-different | - | - | - |
| OU-07 | Viewing an outlet must not change active operational outlet | n/a | n/a (no screen) | n/a until built | - | - | - |

## Module 11 - Profile (store, owner, security)

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| PF-01 | Edit store name / address / contact phone / email / owner name | W:Profile.tsx:72,177-183; server W:src/server/services/profile.ts:35-52 (PUT, OWNER, W:api/v1/profile/route.ts:17) | M:features/owner/presentation/store_profile_screen.dart:167-189, owner_profile_screen.dart:190-226 -> OwnerBloc -> owner_repository.dart:1342-1380 `_updateStoreProfileDirect` / `_updateStoreProfileOffline` (queued) -> PUT `profile` | Impl | none | OFF-ok (queued) | - |
| PF-02 | Sign-in phone shown separately (read-only) from contact phone | W:Profile.tsx:178-179 | M:owner_profile_screen.dart:217 (`SIGN-IN PHONE`); editable field labelled just "PHONE" (:197) not "Organization contact" | Part (copy only) | none | OFF-ok | S |
| PF-03 | Billing card: plan name, deposit, annual fee, paid-through | W:Profile.tsx:107-112 (data from page `storeInfo`, not from v1 `/profile`: `Profile` DTO has no plan fields, W:profile.ts:14-24) | M:subscription_screen.dart (paid-through/status only; searched `planName`, `deposit`, `annualFee` in lib: none) | Miss | BE: needs plan/deposit/fee on an owner-only endpoint (extend `GET /profile` or `/auth/status`) | ON | M |
| PF-04 | Outlets card in profile (code, status, address, opened) | W:Profile.tsx:125-140 | not found | Miss | BE (same as OU-03) | ON | S after OU-03 |
| PF-05 | Change password (min 8, old required, throttled, returns new token) | W:Profile.tsx:60-64,192-250; API W:api/v1/auth/change-password/route.ts:17-50 (429 + Retry-After; new `token` returned) | M:features/owner/presentation/change_password_screen.dart and features/profile/presentation/change_password_screen.dart (two copies) -> owner_repository.dart:1782-1795 / auth_repository.dart:243-258 -> POST `changePassword`; saves returned token (`saveToken`) | Impl (429 Retry-After value not surfaced: `RateLimitException`, dio_interceptors.dart:317) | none | ON | - |
| PF-06 | Client rule: new password must differ from current | W:Profile.tsx:60-64,237 (client only; server does not enforce) | not verified in mobile screens | Part / Not verified | none | - | S |
| PF-07 | "Password last changed" | W:Profile.tsx:100-101, derived from `user.updatedAt` (W:profile/page.tsx:35) - misleading, any user update changes it: web-only defect, do not copy | not present | Miss, intentionally do not copy until a real timestamp exists | BE (needs `passwordChangedAt`) | - | S |
| PF-08 | Employee account view (name, role), logout, switch store | W:Profile.tsx:82 (`Account`), :147 sign out | M:features/profile/presentation/profile_screen.dart:354-405 | Impl | none | OFF-ok (logout parks queues, auth_repository.dart:17) | - |
| PF-09 | Read-only profile when locked | W:Profile.tsx:26,72,92 (`readOnly`) | not found | Miss (Module 13) | BE+mobile | - | M |

## Module 12 - Payment methods

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| PM-01 | List org-enabled platform methods (incl. disabled for owner) | W:PaymentMethodsSettings.tsx:10; API W:api/v1/payment-methods/route.ts | M:features/owner/presentation/payment_methods_screen.dart; owner_repository.dart:1165 GET `paymentMethodsAll` | Impl | none | OFF-ok (cached) | - |
| PM-02 | Enable / disable (organization-wide) | W:PaymentMethodsSettings.tsx:15-18,42-50 | M:payment_methods_screen.dart:215-221 -> `TogglePaymentMethodEvent` -> owner_bloc.dart:583 -> owner_repository.dart:1214 PATCH `paymentMethodDetail` (queued when offline, :1228-1240) -> W:api/v1/payment-methods/[id]/route.ts (OWNER) | Impl | none | OFF-ok (queued) | - |
| PM-03 | Confirm before disabling | W:PaymentMethodsSettings.tsx:13,45 (`pendingDisable`) | M:payment_methods_screen.dart:31-45 (`CentredDialog` "Disable {name}?") (28 Sep fix confirmed in code) | Impl | none | - | - |
| PM-04 | No add / rename (platform catalogue only) | W: Super Admin only (W:src/app/api/v1/super-admin/payment-methods) | none (correct) | Intentionally-different | - | - | - |
| PM-05 | Empty-list handling at checkout | W:OrderEditorContainer.tsx:132,141 | M:checkout_screen.dart:370 | Impl | none | - | - |

## Module 13 - Subscription / access states

Server model: `getStoreAccessStatus` (W:src/server/auth/session.ts:~574-600) yields `blockedReason` and `subscriptionState` (ACTIVE / TRIAL / TRIAL_ENDING / SUBSCRIPTION_ENDING / RESTRICTED). `requireStoreSession` accepts `allowRestricted` (lapsed or billing-pending reads) and `allowLockedReadOnly` (admin lock, record browsing only) (W:session.ts:246-250, 313-333). `billing_pending` is now enforced server side behind env flag `MOBILE_BLOCK_TERMS_NOT_SET` (default false) via `isBillingPending` (W:session.ts:199-211, uncommitted).

Which v1 routes opt in to restricted reads (searched `allowRestricted` in W:src/app/api/v1): `GET /orders`, `GET /orders/sync`, `GET /orders/{code}`, `GET /orders/{code}/invoice`, `GET /dashboard/rollups`, `GET /sync/status` (web-only probe, unused by mobile). NOT opted in: `GET /dashboard`, `/expenses*`, `/employees*`, `/products`, `/profile`, `/payment-methods`, `PDF route`, all writes. No v1 route uses `allowLockedReadOnly` (searched: only web pages and session helpers).

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| SB-01 | Trial status strip (non-dismissible; end date; warning near end; owner action link) | W:AdminChrome.tsx:107-110; W:AdminProvider.tsx:11 (`TrialStatus`) | M: no global strip. Trial/renew shown as badge in More (more_screen.dart:378-401) and card in subscription_screen.dart:67-140 via plan_status_helper.dart:35-140; `trialEndsAt`/`subscriptionState` parsed (user_model.dart:61-62,85-86) | Part | none (data present on `stores[]`) | OFF-ok (from cached store summary) | S |
| SB-02 | Pre-expiry paid-plan warning banner (7 days; owner date, employee generic) | W:AccessNotices.tsx:60-70; used W:AdminScreenContainer.tsx:179 | M:plan_status_helper.dart:62-80 (`SUBSCRIPTION_ENDING`, subtitle only); no banner on work screens; employee privacy rule (no financial detail) not implemented separately (screens shown to owner only in More/Subscription) | Part | none | OFF-ok | S |
| SB-03 | Plan expired -> blocking screen with per-role copy | W:AccessNotices.tsx:21-30,45-54 | M:shared/widgets/blocked_screen.dart:63-96; main.dart:547-562; auth_bloc.dart:127,254-282 | Impl (but see SB-07: also blocks all reads) | none | - | - |
| SB-04 | RESTRICTED read-only workspace (history reads still work) | W: pages open with locked-read-only (W:orders/page.tsx:21, outlets/[outletId]/page.tsx:20) and mutation controls disabled via `readOnly` props (Employees.tsx:7, Catalogue.tsx:56, Profile.tsx:26, OrderDetails.tsx:13) | not found: any 403 with a `reason` becomes `AccessBlockedState` (main.dart:388-405 -> auth_bloc.dart:254-282); no read-only mode (searched `readOnly`, `isLocked`, `restricted` in lib/features) | Miss | BE (partial): reads for orders/sync/invoice/rollups already pass in `allowRestricted`; still needed: restricted-read opt-in for `/dashboard`, `/expenses` GET, `/employees` GET, `/products`, `/profile`, `/payment-methods`, and `allowLockedReadOnly` on any v1 route for admin locks; plus mobile mode | ON | L |
| SB-05 | Admin lock (`store_locked`) read-only with banner "Store locked - Read-only" | W:AdminChrome.tsx:106 | M:blocked_screen.dart:51-54 (full block) | Miss (same as SB-04) | BE+mobile | - | L |
| SB-06 | `billing_pending` handling | W:AccessNotices.tsx:31-37, server W:session.ts:199 | M:blocked_screen.dart:98-133, 215-232. DEFECT: owner copy says "Complete payment on the KlenPOS web dashboard" (:120) but no web payment route exists for owners (contract section 2 note); `billingUrl` is never passed in main.dart:548-561, so the "Complete payment" button (:215-229) can never show | Part / copy defect | none (copy) | - | S |
| SB-07 | Queued offline actions under block: retained and replayed after access returns | W: n/a | M:blocked_screen.dart:177-196 promises automatic replay, but a 403 on a bulk-sync batch dead-letters the whole outlet group regardless of `reason` (orders_repository.dart:696-709, 845-870, labelled "outlet access changed"); revival requires the user to trigger it (sync_engine.dart:309-310, owner_repository.dart:1767) | Defect / offline-replay risk | mobile-only | n/a | M |
| SB-08 | Block states stay distinct: inactive membership vs locked vs archived vs lapsed | W:AccessNotices.tsx:11-55 | M:blocked_screen.dart:41-135 (membership_inactive, store_locked, no_outlet_assigned, store_archived, payment_lapsed, billing_pending) | Impl | none | - | - |
| SB-09 | Refresh of access state while app is open | W: server component refetch per navigation | M: cold start `CheckAuthStatusEvent` (main.dart:369) and reactive 403 (main.dart:388-405); resume only runs Remote Config gate + stale sync (main.dart:261-274, app_resume_sync.dart); no `/auth/status` on resume (HANDOFF open item) | Part | none | ON | S |
| SB-10 | Renewal makes access resume without re-login | W:session.ts live check each request | M:blocked_screen.dart `onRetry` -> `CheckAuthStatusEvent` (main.dart:553) | Impl | none | ON | - |
| SB-11 | Super Admin trial/billing management | W:src/app/api/v1/super-admin/**, super-admin UI | none | Intentionally-different (web-only) | - | - | - |
| SB-12 | `must_change_password` 403 mid-session routes to set-password | contract section 1 | M: `reason` `must_change_password` reaches `AccessBlockedState` and shows the generic "You do not have access" text (auth_bloc.dart:277-283, blocked_screen.dart:135; no `must_change_password` handling anywhere in lib: searched). Cold start/login path handles it correctly (auth_bloc.dart:106-109). Reachability low because employee password reset/updates also revoke sessions (employees.ts:282) | Part (edge case) | none | - | S |

## Module 14 - Announcements / notices

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| AN-01 | Store-audience published announcements strip (info/warning tone, optional safe action link, revision-based dismissal, targeting by organization, 60 s refresh) | W:AdminChrome.tsx:111 (`WorkspaceAnnouncements audience="store"`); service W:src/server/services/workspace-announcements.ts:34-40 (`publishedAnnouncements`, strips `storeIds`) | not found (searched `announcement`, `notice` in lib: only unrelated strings) | Miss | BE: needs `GET /api/v1/announcements` (no route exists; searched src/app/api for "announcement": none) | ON (policy for cache/dismissal to decide) | M |
| AN-02 | Super Admin authoring of announcements | W:src/app/super-admin/(shell)/announcements/page.tsx; W:src/features/super-admin/actions/announcements.actions.ts | none | Intentionally-different (web-only) | - | - | - |
| AN-03 | Action link safety (relative path or https only) | W:workspace-announcements.ts:8-11 | n/a | n/a until AN-01; mobile must map links to in-app routes or `launchUrl` allow-list | - | - | - |

## Module 15 - Auth / session

| ID | Capability | Web cite | Mobile cite | Status | Blocker | Offline | Size |
|---|---|---|---|---|---|---|---|
| AU-01 | Phone + password login, 429 on repeated failure | W:api/v1/auth/login/route.ts (throttle now awaited and DB-backed, W:src/server/auth/throttle.ts + migration `20261001120000_...auth_throttle...`) | M:features/auth/data/auth_repository.dart:40-75; body `{phone,password}`; login_screen.dart; `RateLimitException` (dio_interceptors.dart:317) | Impl | none | ON | - |
| AU-02 | Forced first-login password change | W:api/v1/auth/set-password/route.ts; server gate for all other routes (contract section 1) | M:auth_bloc.dart:106-109 `MustChangePasswordState`; reset_password_screen.dart (main.dart:544); auth_repository.dart:230 | Impl | none | ON | - |
| AU-03 | Session revocation: 401 -> sign out; password change/reset kills sessions | W:session.ts:118-166,196 (`revokeAllSessionsForUser`) ; employees.ts:282; profile.ts (changeUserPassword) | M:main.dart:384-390 (`SessionRevokedEvent`), auth_repository.dart:315 logout | Impl | none | ON | - |
| AU-04 | Outlet-scoped 403 (reason-less) -> re-resolve outlet / re-login | W: server | M:main.dart:393-396 `_handleOutletAccessLost`, auth_bloc.dart:254-274 | Impl | none | - | - |
| AU-05 | Resume refresh of session / membership / subscription | n/a | not on resume (see SB-09) | Part | none | ON | S |
| AU-06 | Logout keeps unsynced queues per store and restores on next sign-in | n/a | M:auth_repository.dart:17,75 (`keyParkedUnsynced`, `_restoreParkedQueues`) | Impl (HANDOFF claim confirmed by symbol presence; replay not re-traced) | none | OFF-ok | - |
| AU-07 | Session token is the cookie value / bearer, not guessable DB id | W:session.ts diff: cookie now `session.token` (uncommitted); old cuid-id cookies stop working | M: bearer token only (secure_storage.dart) | Impl (web fix is uncommitted; HANDOFF pending item 4 is stale for the working tree) | none | - | - |
| AU-08 | Per-tenant idempotency keys | W: migration `20261001120000_...` + `storeId_idempotencyKey` lookups in orders.ts/expenses.ts/employees.ts (uncommitted) | M: sends `idempotencyKey` (cart_bloc.dart:257; expenses) - unaffected | Impl on web working tree; not deployed/verified | none | - | - |
| AU-09 | Switch store (multi-store users) | W:StoreSwitcher.tsx | M:features/shell/presentation/store_switcher_dialog.dart; auth_repository.dart:263 `selectStore` | Impl | none | OFF-ok | - |
| AU-10 | Dashboard "All stores" aggregate view across organizations | W:AdminChrome.tsx:90 (`selectDashboardAllStoresAction`) | not found | Miss / likely N-A (store-level scope is the mobile model) | decision | - | M |

---

## 3. Changes since the 27 Sep checklist (WEB-MOBILE-FEATURE-GAPS.md)

### 3a. Unchecked items now done in code (evidence)

| Checklist item | Evidence | Caveat |
|---|---|---|
| D1 booked-sales trend (D1.1) | M:dashboard_model.dart:75,116 retains `bars`; M:owner_dashboard_screen.dart:320 plots `bars`; W:admin.analytics.ts:119 | D1.2 (same-duration comparison) and D1.3 (zero vs missing, fallback at owner_dashboard_screen.dart:517-523) still open; D1.4 not verified |
| E1 details / edit / delete (E1.1, E1.2) | M:expense_detail_screen.dart, edit_expense_screen.dart, owner_repository.dart:566-624, owner_bloc.dart:285,323; W:api/v1/expenses/[id]/route.ts:7,18 | Both sides uncommitted (web route file is untracked). E1.3 satisfied by existing contract text (MOBILE-API-CONTRACT.md section 5 notes). See defects EX-13/14/15 |
| E2 chosen paid date (E2.1) | M:expense_detail_screen.dart:42-62; owner_repository.dart:626-640,660-670,1555-1562 (queued + replay carry `paidDate`); W:expenses/[id]/pay/route.ts:13 | E2.2 (chart counts payment on chosen date) relies on server; not verified |
| E3 outlet attribution (E3.1) | M:expenses_screen.dart:958-959,1111; expense_model.dart:3,29; list/detail labels expenses_screen.dart:746, expense_detail_screen.dart:117 | E3.2 (queued expense stays in original scope after switch) not traced |
| S1.1-S1.3 | already ticked; code confirmed (staff_screen.dart:625,541-542; staff_model.dart:41; owner_repository.dart:1645) | S1.4 device check pending |
| A2 payment-method disable confirmation | M:payment_methods_screen.dart:31-45 | - |
| A1.1 (login phone shown separately) - half | M:owner_profile_screen.dart:217 | editable field not relabelled "Organization contact" |
| N1 (trial/renewal state) - half | M:plan_status_helper.dart:35-140, more_screen.dart:378, subscription_screen.dart:67 | not a global strip; see SB-01/02 |
| D3 / O1 | already ticked, code confirmed (D-12, EO-04) | - |

### 3b. Unchecked and still open (no evidence of progress)
D2 per-outlet cards (D-14); D1.2/D1.3; O3 public invoice link (INV-06); P1/P2 (decision / legacy unit); S2 password reset; L1 outlet directory/detail; A1.2/A1.3 billing and outlet facts; N2 locked read-only; N3 announcements; N1.2/N1.3 strip and IST boundaries (not verified).

### 3c. Claims that did NOT hold up (or are stale)

| Claim (source) | Reality |
|---|---|
| "Expenses: edit, delete, chosen paid date, outlet attribution; needs new backend routes" (HANDOFF 1 Oct pending #1) | Stale: routes exist (W:expenses/[id]/route.ts, pay/route.ts:13) and mobile implements all four. Both sides uncommitted, backend tests (W:tests/expense-routes.integration.test.ts) not run by me |
| "Expense edit/delete/backdated-pay have no REST endpoint" (HANDOFF 28 Sep) | Stale, same reason |
| "Staff editor has no outlet assignment ... contract doesn't carry outlet fields" (HANDOFF 28 Sep) | Stale: done 30 Sep (ST-04, contract section 5 "Employee outlet assignments") |
| "API pay POST does not consume a date" (27 Sep E2) | Stale: W:expenses/[id]/pay/route.ts:13 |
| "Rollups lets an employee omit outlet and silently fall back" (HANDOFF 28 Sep) | Fixed: W:dashboard/rollups/route.ts:34-37 |
| "Employee can fetch another outlet's invoice PDF" (HANDOFF 28 Sep) | Fixed and committed in e94a220: W:order-invoices.ts:76-88 used by both `/api/v1/.../invoice/pdf` and the web PDF route |
| "billing_pending not enforced server-side; session cookie id is a cuid; login throttle per warm instance; idempotency unique global" (HANDOFF 1 Oct #4) | All four addressed in the web working tree (uncommitted): W:session.ts:199-211,327-333 (billing pending), session.ts cookie now `session.token`, W:throttle.ts + migration `20261001120000_...` (DB-backed `auth_throttle`, `storeId_idempotencyKey` uniques). Not deployed; migration not applied anywhere I can see |
| "Mobile API readers lack allowLockedReadOnly opt-in" (27 Sep N2) | Half stale: readers for orders/sync/order/invoice/rollups already pass `allowRestricted` (lapse/billing-pending). Admin-lock (`LOCKED`) still blocked on every v1 route; most other readers still not opted in |
| BlockedScreen "queued actions will go through automatically once access is restored" (M:blocked_screen.dart:194) | Not reliable: bulk-sync 403 dead-letters the outlet group for any reason (orders_repository.dart:696-709); needs a user-triggered revive |
| "Complete payment on the KlenPOS web dashboard" for billing_pending owners (M:blocked_screen.dart:120) | No such web route for owners (contract section 2 note); `billingUrl` never supplied (main.dart:548-561) |
| Trial banner fix "unverified" (HANDOFF 28 Sep) | Verified in code for More/Subscription only (plan_status_helper.dart); no strip on work screens |
| "Product editor slab validation looser" (HANDOFF 28 Sep) | Still true (PR-04) |
| Contract line "every response Cache-Control private, no-store" (MOBILE-API-CONTRACT.md section 1) | `GET /products` sends `private, max-age=30` (W:handler.ts:138-139) |
| Test counts 800/800 flutter, 118/118 backend (HANDOFF) | Not run (read-only audit); cannot confirm. Several new tests (mobile expenses_ui_details_edit_test.dart, web expense-routes/billing-pending/per-tenant-idempotency) are untracked |
| "../laundry_pos/audit/ (199 bullets)" (brief) | Directory does not exist in the web tree; only `scripts/qa_audit.mjs` and QA-*.md notes |

---

## 4. Prioritised gap list

Sizes: S <= 0.5 day, M ~ 1-2 days, L > 2 days (rough, mobile side unless stated).

### Batch A - mobile-only (no backend change)

| # | Item | Rows | Size | Depends on |
|---|---|---|---|---|
| A1 | Replay safety on access 403s: do not dead-letter or relabel "outlet access changed" when 403 carries `reason` (payment_lapsed, store_locked, billing_pending, membership_inactive, must_change_password); keep queued, auto-resume after access returns; align BlockedScreen text | SB-07 | M | none (do first; also prerequisite for B3) |
| A2 | Expense edit/delete hardening: disable edit/delete for `LOCAL-` ids; patch all scope caches (or refetch All + origin + target outlet) after edit/delete; revert detail view when update fails; paid-expense wording in delete confirm | EX-12..15 | S | none; before committing the expense work |
| A3 | Staff password reset (and optional password on edit) via existing `PUT /employees/{id}` `{name, phone, password}`; online-only, never queued; copy "sessions end, must change password" | ST-07, ST-08 | M | none |
| A4 | Per-outlet performance cards in All-outlets scope from existing `GET /dashboard/rollups` (add endpoint constant, model, card, yesterday comparison) | D-14 | M | none |
| A5 | Dashboard: overdue + "Needs attention" row; expenses-this-month headline; first-use empty state; true-zero vs missing distinction | D-11, D-04, D-17, D-02 | S | none |
| A6 | Previous-period comparison series (second request with shifted range) | D-06 | M | none |
| A7 | Public invoice link: share/open `/i/{accessToken}/view` when invoice is final, keep local PDF/print/offline | INV-06 | S | none |
| A8 | Notices: global non-dismissible trial/renewal strip (owner detail, employee generic), billing_pending copy fix, `/auth/status` refresh on resume, `must_change_password` 403 -> set-password screen | SB-01, SB-02, SB-06, SB-09, SB-12, AU-05 | M | none |
| A9 | Partial "received now" at order creation | POS-08 | S | none |
| A10 | Small parity polish: slab validation, relabel contact phone, surface `Retry-After`, "Organization-wide" orders filter | PR-04, PF-02, PF-05, OO-07 | S each | none |

### Batch B - needs backend first

| # | Missing endpoint / change | Mobile work | Size (BE + mobile) | Depends on |
|---|---|---|---|---|
| B1 | `GET /api/v1/announcements` (published, audience/store derived from session, strips `storeIds`, includes `revision`, tone, safe action) | strip UI, dismissal keyed by id+revision, offline cache/expiry policy | M + M | none |
| B2 | `GET /api/v1/outlets` and `GET /api/v1/outlets/{id}` (all statuses, address, opened date, contact, employees; owner only) | directory + detail screens; reuse dashboard scope for analytics | M + L | none |
| B3 | Restricted/locked read-only mode: add `allowRestricted` (lapse) to `GET /dashboard`, `/expenses`, `/employees`, `/products`, `/profile`, `/payment-methods`; decide `allowLockedReadOnly` for v1; ensure mutations return distinct `reason`; expose lock flag (`/profile` already returns `status`/`isLocked`, W:profile.ts:14-24) | read-only workspace, persistent banner, disabled actions | M + L | A1 |
| B4 | Billing/plan facts for owners (plan, deposit, annual fee, paid-through) on an owner-only endpoint (extend `/profile` or `/auth/status`) | profile billing card | S + S | none |
| B5 | Real `passwordChangedAt` | show in Security | S + S | none |
| B6 | Owner payment path for `billing_pending` (none exists) | replace dead-end copy with real action | product decision | decision |
| B7 | Optional dedicated reset-password route (not needed; PUT works) | - | S | none |

### Batch C - intentionally deferred / do not change
Product category vocabulary (PR-05, data is free-form; agree before changing); legacy "Confirm unit" (PR-07, only if legacy rows exist in prod); server-rendered invoice PDF (INV-02, local PDF is the offline-first design); dashboard 14-day default (D-07); offline product writes (PR-06); multi-select outlet filter on orders (OO-07 simplification); dashboard all-stores aggregate (AU-10); outlet provisioning (OU-06); Super Admin and platform billing.

### Top 10 (ranked by risk then value)
1. A1 / SB-07: queued orders and owner actions dead-lettered by any 403 (including payment lapse), while the UI promises automatic replay.
2. A2 / EX-13..15: new expense edit/delete can hit `LOCAL-` ids, leaves other scope caches stale, and shows unsaved edits on failure; also entire feature is uncommitted.
3. B3 / SB-04: no restricted/locked read-only workspace (history unreadable during lapse; backend already half-ready).
4. A4 / D-14: per-outlet cards; endpoint exists.
5. A3 / ST-07: staff password reset; endpoint behaviour exists.
6. B1 / AN-01: announcements (needs endpoint).
7. B2 / OU-03/04: outlet directory and detail (needs endpoints; closed/relocated outlets invisible today).
8. A8: trial/renewal strip, billing_pending dead-end copy, status refresh on resume.
9. A7 + A9: public invoice link; partial payment at creation.
10. A5/A6 + B4: overdue/attention, previous-period comparison, billing card.

---

## 5. Risks (security-relevant first)

1. Cross-outlet read (closed): invoice PDF/JSON now check outlet membership for employees (W:order-invoices.ts:76-88; W:invoice/route.ts:16-19; W:invoice/pdf/route.tsx:16). Verified in code and in commit e94a220. Mobile never calls the PDF route. I did not run the tests.
2. Role gating: every expense, employee, product-write, profile-write and payment-method route is `requireApiStoreSession(req,'OWNER')` (checked: expenses/route.ts, expenses/[id]/route.ts, pay/route.ts, employees/[id]/route.ts, products/route.ts:17, profile/route.ts:17). Employee-only 403s for orders/rollups require an outlet header (orders/route.ts:32-37, rollups/route.ts:34-37). `GET /dashboard` is OWNER-only but takes an arbitrary `outletId` query without validating it belongs to the org (W:dashboard/route.ts:20); results are still store-scoped so there is no cross-tenant leak, only an empty result - low.
3. Offline replay: (a) SB-07 dead-lettering on access 403s; (b) legacy `toggle_staff_active` replay is a non-idempotent toggle (M:owner_repository.dart:1628-1631) - only for queue items created before the 30 Sep change; (c) expense edit/delete are online-only, which is correct, but offline-created expenses (`LOCAL-` ids) are not protected from them (EX-13); (d) mark-paid replay resolves LOCAL ids via `idMap` and carries `paidDate` (good, owner_repository.dart:1555-1562).
4. Silent re-attribution: `updateExpense` omits `outletId` when null and the server then makes the expense organization-wide (W:contract section 5; M:owner_repository.dart:589). Correct for the "Organization-wide" choice, but any future caller passing null for an outlet-bound expense would re-attribute silently. Prefer an explicit flag.
5. Deploy ordering: stage mobile depends on backend employee-list change (HANDOFF). Additional uncommitted backend changes (sessions keyed by token, DB-backed throttle, per-tenant idempotency uniques via migration `20261001120000_...`) need a migration run and will sign out existing web cookie sessions once. Mobile bearer tokens are session tokens already; I did not verify they survive the session-table change.
6. Data-loss exposure: both repos hold the expense work (and web migration/tests) as uncommitted or untracked files; `git clean`/stash would lose them.
7. `billing_pending` flag (`MOBILE_BLOCK_TERMS_NOT_SET`, default false): turning it on locks unbilled orgs with no owner payment path, and the mobile screen directs owners to a web payment that does not exist (SB-06).
8. Reads under lapse: mobile blocks everything on `payment_lapsed`, but some reads would succeed server-side (orders etc.). Inconsistent user experience when partial 403s arrive mid-session (first 403 flips the whole app to BlockedScreen, main.dart:388-405).
9. Phone validation drift: server accepts 8-15 digit phones; mobile is strict. Orders/employees created on web with odd phones may be unsearchable by 10-digit patterns on mobile (minor).

---

## 6. Not verified (could not confirm from code alone)

- Nothing was built, run or tested: all test counts, `flutter analyze`, backend tests, migration application, and every device/simulator behavior are unverified. The simulator was not touched.
- Codex's `../laundry_pos/audit/` artifacts are absent; I could not cross-check the 199 bullets, only my own derived 151.
- "Impl" rows for list/filter/detail UI were verified at screen + repository-call level, not every widget branch: owner/employee register filter labels and semantics (due-today/late vs web, OO-06, EO-05), order detail section wording (OD-01..04), POS slab calculation parity with server pricing (POS-02, `W:src/server/pricing.ts` not compared line by line), invoice PDF visual equivalence (INV-07), default delivery date and past-date rejection (POS-04).
- Whether the dashboard recent-orders and tile drill-downs behave as HANDOFF says on device (pending item 2).
- Whether the cached month/custom-range labels stay truthful offline (D1.4) and whether queued expenses stay in their original scope after an outlet switch (E3.2) - code paths for these were not traced.
- How the owner queue (`owner_repository` `processPendingOwnerActions`) reacts to access 403s; I traced only the orders queue (orders_repository.dart:696-709).
- Whether the untracked web routes and tests are complete and passing (expenses/[id]/route.ts, tests/expense-routes.integration.test.ts, tests/billing-pending.integration.test.ts, tests/per-tenant-idempotency.integration.test.ts).
- Server-side semantics not opened: `updateExpense`/`deleteExpense` series behavior beyond the contract text, `createExpense` with no outlet, `markExpensePaid` future-date rejection (contract says rejected), pricing on `createOrder`.
- Exact line numbers for some mobile staff/profile/order-detail rows are to the nearest block (e.g. staff_screen.dart:382-460, order_detail_screen.dart body); spot-checked, not exhaustively.
- Web pages' `QA-*.md` notes in `../laundry_pos` were not read.
- GET `/products` HTTP caching effect on mobile freshness after a product edit (Dio cache behavior not inspected).
