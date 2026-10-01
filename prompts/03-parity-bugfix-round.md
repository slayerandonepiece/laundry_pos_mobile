# Prompt 03 — Web/mobile parity bug-fix round (2026-09-29)

Scope boundary: CLAUDE.md. Touch only the files named per item. No opportunistic
refactors. Backend contract wins on conflicts:
`../laundry_pos/.agents/MOBILE-API-CONTRACT.md`. Do not commit.

Work items in this order (B1 first — it is a money bug). After EACH item run
`flutter analyze` and the tests named in that item, and report the output.
Finish with the full `flutter test` (baseline: 402 passing).

---

## B1 — Delivered order with balance due: payment can no longer be collected (CRITICAL)

Root cause (verified):
- `lib/features/orders/presentation/order_detail_screen.dart:493` — the
  `!isDelivered` branch owns "Collect payment & deliver" / "Record payment".
  The `else` branch (:577, "Settled / Delivered Flow") renders only the invoice
  card and View/WhatsApp buttons. A delivered order with `balanceDue > 0` has
  no payment action anywhere.
- `lib/features/orders/presentation/dialogs/status_dialog.dart:270-290` lets the
  user "Deliver anyway" with a balance, which lands the order in that dead end.
- The WhatsApp text at order_detail_screen.dart:661 says "(Paid in full)"
  unconditionally.
- `orders_list_screen.dart:633` only shows the quick action for
  `isReady && !isDelivered`.

Do:
1. In the delivered branch, when `order.balanceDue > 0`, show a prominent
   "Record payment" `PrimaryButton` that opens `RecordPaymentDialog.show`
   (it calls `RecordPaymentEvent`, which does NOT change status — correct here),
   plus a warning `AppInset` "₹X still due on this delivered order".
2. Hide the invoice card until `isPaidInFull` (invoices are created only when
   paid in full + delivered — see orders_repository.dart:294). When paid,
   behaviour is unchanged.
3. WhatsApp text: say "Paid in full" only when `isPaidInFull`; otherwise
   "Balance due: <amount>".
4. Orders list card (`orders_list_screen.dart` ~:633): for
   `isDelivered && hasBalance`, show a "Collect ₹X" button opening
   `RecordPaymentDialog`. Do the same in `owner_orders_screen.dart` if its card
   has an equivalent action area (inspect first; if it has none, only make sure
   the tap-through detail screen works).
5. After `RecordPaymentEvent` succeeds on a delivered order that becomes fully
   paid, the invoice must be generated: in `_onRecordPayment`
   (orders_bloc.dart:249) when `updated.isDelivered && updated.isPaidInFull &&
   updated.invoice == null`, fire-and-forget `getOrCreateInvoice` exactly as
   `_onCollectPayment` does (:219-231). Do not await it before emitting.
6. Tests: add to `test/` (find the existing orders bloc / order detail widget
   tests and extend them): delivered+balance shows "Record payment"; delivered+
   paid shows invoice and no payment button; `_onRecordPayment` on a delivered
   order triggers invoice retrieval.

## B2 — "Syncing data" banner shows after every screen load / outlet switch

Root cause (verified): `SyncManager.startSync('Fetching latest from cloud...')`
is called from every read-refresh: owner_repository.dart lines 77, 146, 387,
714, 839 and pos_repository.dart:64. Each dashboard/expenses/etc. load
therefore flashes the sync banner even though it is a silent background refresh
of already-cached data. `SyncEngine._runSync` (sync_engine.dart:122) is
already correct: it shows the banner only when `getTotalPendingCount() > 0`.

Do:
1. Banner is for (a) pushing queued local changes, (b) first-ever load of an
   outlet with NO cache. Remove `startSync` from the six read-refresh sites
   when a cache exists for that data (keep it when there is no cache, so the
   very first cold load still shows progress). Keep the matching
   `completeSync/setOffline/setError` behaviour: they must never leave the
   banner stuck, and `setError` on a failed *background* refresh with cache may
   stay.
2. Outlet switch (`OutletScopeCubit.select` / `selectAllOutlets`): after the
   first successful sync of an outlet, switching to it again must not show the
   banner. Use `LocalCacheService.hasCachedOrdersFor` (already used by the
   cubit) as the "has cache" test; verify how orders_list_screen /
   owner_orders_screen react to scope changes and make them refresh silently
   when cache exists.
3. Tests: extend `test/` sync/repository tests: with cache present, a dashboard
   fetch never emits `SyncStatus.syncing`; with no cache it does.

## B3 — Single-outlet user can still see/select outlets

Root cause (verified): `lib/shared/widgets/outlet_title_switcher.dart:25-271`
and `_OutletSelectionSheet` (owner_orders_screen.dart:1257) — inspect whether
they gate on `scope.allowed.length > 1`. `OutletScopeCubit.hydrate`
(outlet_scope_cubit.dart:66-114) already pins employees with 1 outlet, but for
an OWNER with exactly 1 outlet it still emits `allOutlets: true` and a
switcher with "All outlets".

Do: when `scope.allowed.length <= 1`, the switcher and any outlet filter/sheet
render NO picker and NO "All outlets" (plain static title/label). For owners
with exactly one outlet, hydrate should set `activeOutletId = allowed.first.id`
and `allOutlets = false`. Multi-outlet behaviour must not change. Tests in the
existing outlet_scope_cubit / switcher tests.

## B4 — Login error is inline (pushes the form down) instead of a banner

`lib/features/auth/presentation/login_screen.dart:120-157` builds the error as
an in-flow `Container` above the fields, shifting the layout. Replace with a
top-anchored overlay banner: wrap the body in a `Stack`; position the same
styled banner at the top (below the status-bar inset), animated slide/fade,
dismissible (X), auto-dismiss after ~6s, `SafeArea`-aware, no layout shift of
the form. Keep the same messages and colours (`AppColors.dangerBg/dangerBorder`).
Update `test/` login widget tests accordingly (find with graft:
`graft ask "login screen widget test"`).

## B5 — Organization created but not billed must be blocked at login

Facts: login/auth-status already return `subscriptionState` (`ACTIVE`, `TRIAL`,
`TRIAL_ENDING`, `SUBSCRIPTION_ENDING`, `RESTRICTED`), `blockedReason`
(`membership_inactive|store_locked|store_archived|payment_lapsed`),
`paidThroughDate`. Existing handling: auth_bloc.dart:127/163/243 (blockedReason
→ blocked screen) and plan_status_helper.dart:102 (RESTRICTED banner only).

**Before coding, do this investigation and report it:** in `../laundry_pos`
find what a freshly created, never-paid organization returns for
`subscriptionState`, `blockedReason` and `isLocked` (grep
`src/server/api/membership-context.ts` and the org-creation action). Do NOT
guess. Then:
- If it already yields `RESTRICTED` / a `blockedReason`: route it to a
  "Billing not completed" screen (reuse the existing blocked screen if
  suitable) with: explanation, "Complete payment" (opens the web billing URL
  via `url_launcher`, only if the backend exposes one — otherwise show "Contact
  support / complete payment on the web dashboard"), and a "Retry" button that
  re-runs `checkSession` and proceeds if the state cleared. Owner and employee
  copy differs (employee: "Ask your owner to complete billing").
- If the backend returns nothing distinguishing for never-billed orgs: STOP,
  do not implement, and report exactly what the backend must add.

## B6 — Dashboard: tiny labels; needs 7/30/90-day charts that fit on one screen

Verified: fixed 10pt axis text (owner_dashboard_screen.dart:1087,1117,1413,
1443), `FittedBox(scaleDown)` on 28pt KPI numbers (:557,:601) shrinks them on
narrow phones, chart height fixed at 180 (:1047), period picker is a
`PopupMenuItem` menu (today/7d/30d/quarter/custom, :770).

Reference (5 screenshots attached by the user, from another app): period is a
row of pill chips `7 Days | 30 Days | 90 Days`; 7d = 7 daily points labelled
"22\nSep"; 30d = 4 weekly buckets labelled "Aug 30 -\nSep 05"; 90d = 3 monthly
buckets labelled "01 Jul -\n30 Jul"; y-axis has 4 evenly spaced ticks; area
under the line; last-point tooltip; everything fits without scrolling.

Do: (1) replace the popup with pill chips 7d/30d/90d (keep 'custom' reachable
via an overflow/calendar icon so the existing custom range still works; keep
`_selectedPeriod` semantics; map 'quarter' → 90d). (2) Verify what buckets the
backend `/api/v1/dashboard` returns per range (read the contract + response
model `dashboard_model.dart`); if it returns daily points for 30/90 days,
aggregate client-side into weekly (30d) / monthly (90d) buckets with the
label formats above — do NOT change the API. (3) Chart: min font 11, two-line
x labels, 4 y ticks, light area fill, height from `LayoutBuilder`/screen
fraction (~28% of height, clamp 170–240), show every bucket label for ≤7
points. (4) KPI numbers: keep ≥20pt; use `AutoSizeText`-style only if already
a dependency, otherwise reduce to 22pt with `maxLines: 1` and abbreviate ≥1L as
"₹1.2L". (5) Update the `_shouldShowChartLabel` / `formatChartLabel` tests.

---

## Verification (paste real output for each)
- `flutter analyze` → 0 issues
- `flutter test` → all pass (≥402 + new)
- `git diff --stat` → only files named above + their tests
- Simulator screenshots: login error banner; delivered-with-balance order
  detail (Record payment visible); dashboard 7d/30d/90d.
- State explicitly anything you could not verify.
