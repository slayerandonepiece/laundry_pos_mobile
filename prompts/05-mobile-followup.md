# Prompt 05 — Flutter follow-up to prompt 03 (B2 remainder, B6 remainder, B5 client)

Repo: /Users/reddygona/Documents/skills/laundry_pos_mobile. Read CLAUDE.md first
(scope boundary). Backend contract wins: `../laundry_pos/.agents/MOBILE-API-CONTRACT.md`.
Do not commit. Do not edit `../laundry_pos`.

AUTONOMY: never stop to ask. Ambiguity → pick the option closest to the spec and
existing style, log it in PROGRESS.md (append; do not delete existing lines).
Before each item append "[time] STARTED Fx"; after, "[time] DONE Fx — files |
tests | analyze | assumptions"; if blocked, "[time] BLOCKED Fx — reason" and move
on. Per item run `flutter analyze` and only the tests you touched; run full
`flutter test` once at the end.

Order: F1 → F2 → F3 → F4 (F4 is conditional).

---

## F1 — Outlet switch must not show the sync banner once an outlet has been synced

State after prompt 03: `OrdersRepository.hasCachedOrders()`
(lib/features/orders/data/orders_repository.dart:61) exists but has NO caller.
It was meant for this. Remaining sources of the banner:
- `orders_repository.dart` ~:452 `SyncManager.instance.startSync(...)` inside
  `_processPendingSyncQueueImpl` — verify whether it fires when the queue is
  empty.
- `syncOrdersDelta` and the orders list load path — read them and check whether
  they call startSync / set syncing on an outlet switch when that outlet's
  cache already exists.
- Screens reacting to `OutletScopeCubit` changes:
  `lib/features/orders/presentation/orders_list_screen.dart`,
  `lib/features/owner/presentation/owner_orders_screen.dart`,
  `owner_dashboard_screen.dart`.

Do: trace (use `graft ask "outlet scope change refresh orders"`) what happens on
`OutletScopeCubit.select()` end-to-end. Whenever the target scope already has a
cached orders list (`hasCachedOrders`), show cached data immediately and refresh
silently (no `startSync`, no syncing status). Show the banner only for (a) a
non-empty pending queue push, (b) a scope with NO cache. Use
`hasCachedOrders` at the call sites that need it; if after tracing it is not
needed anywhere, DELETE it (do not leave dead code) and say so.
Tests: with cache for outlet B, switching A→B never emits `SyncStatus.syncing`;
without cache it does; pending queue > 0 still shows "Saving changes to cloud...".

## F2 — Dashboard chart: area fill under the line + data actually follows the chip

Two problems after prompt 03:
1. Reference screenshots have a light area under the line. In
   `owner_dashboard_screen.dart` `_SalesTrendChart` (and the other LineChart
   at ~:1400) add `belowBarData: BarAreaData(show: true, color:
   AppColors.primary.withValues(alpha: 0.10))`. Keep the tooltip on the last
   point if that is cheap; otherwise leave the existing touch tooltip.
2. VERIFIED BACKEND FACT: `/api/v1/dashboard` returns `bars` (sales buckets,
   up to 12, over the requested from/to) and `cash` (income/expense buckets,
   ALWAYS the current calendar month, 5 buckets, ignoring from/to).
   `DashboardMetrics` (lib/features/owner/data/models/dashboard_model.dart)
   only parses `cash`. So the chart may NOT change when the user taps
   7/30/90 Days. Investigate: read `_SalesTrendChart` callers, what data it
   plots, and how `_selectedPeriod` maps to from/to (owner_dashboard_screen.dart
   ~:490-520). Report precisely what is plotted per chip today.
   - If the chart plots `cash` (month-fixed): change it to plot `bars` for the
     selected range (add `bars` to `DashboardMetrics.fromJson/toJson` as a list
     of `{label, amount}`; tolerate it being absent → fall back to current
     behaviour so old cache/older backend still work).
   - Keep the cash/income-vs-expense chart, if one exists, as is.
   - Do NOT aggregate weekly/monthly client-side (backend `bars` may not be
     daily). If the response contains a `granularity` echo or the backend later
     supports `?granularity=day|week|month` (prompt 04, BE2) — send
     `granularity=day` for 7d, `week` for 30d, `month` for 90d ONLY when
     `ApiEndpoints`/contract in ../laundry_pos already documents that param
     (grep the contract; if not documented, do not send it and log it).
Tests: `DashboardMetrics.fromJson` with and without `bars`; chart shows the
`bars` labels for a 7-day fixture (extend test/features/owner_dashboard_screen_test.dart).

## F3 — Verify label formatting against real backend labels

Backend labels come from `dateLabel` and look like `"1 Sep"` or
`"1 Sep–3 Sep"` (en dash, no zero padding) — confirm by reading
`../laundry_pos/src/features/admin/admin.analytics.ts` (`dateLabel`). Check
that `formatChartLabel` (owner_dashboard_screen.dart ~:830-948) turns
`"1 Sep–3 Sep"` into two lines `"01 Sep -\n03 Sep"` (reference style) and
single `"22 Sep"` into `"22\nSep"`. Add test cases with those exact strings if
missing. Fix only if a case fails.

## F4 — Billing-not-completed screen (ONLY if the backend prompt 04 has landed)

Precondition check: read `../laundry_pos/.agents/MOBILE-API-CONTRACT.md` and
grep for `billing_pending`. If it is NOT documented there: mark F4 BLOCKED
("backend BE1 not landed") and STOP this item — write nothing.

If documented:
- `UserStore.blockedReason` (lib/features/auth/data/models/user_model.dart:59)
  comment/known values: add `billing_pending`.
- Follow the existing `payment_lapsed` handling in
  `lib/features/auth/bloc/auth_bloc.dart` (:127, :163, :243) and the existing
  blocked screen (find with `graft ask "blocked store reason screen"`). Add a
  distinct copy for `billing_pending`: title "Billing not completed"; owner:
  "Complete payment to start using your organization." with a primary button
  "Complete payment" that opens the billing URL documented in the contract via
  `url_launcher` (if the contract gives none, hide the button and show "Complete
  payment on the KlenPOS web dashboard"); employee: "Ask your owner to complete
  billing." No button. Always show a "Retry" button that re-runs `checkSession`
  and proceeds if the block cleared. Never store a session as fully signed-in
  while blocked.
- Tests: bloc emits the blocked state for `billing_pending`; widget test for
  owner vs employee copy and Retry.

---

## Final verification (real output, append to PROGRESS.md)
- `flutter analyze` → 0 issues
- `flutter test` → all pass (baseline 414 + new)
- `git diff --stat` → only files named above + tests
- List anything unverified. Do not claim a check you did not run.
