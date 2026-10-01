# KlenPOS 1.0.4 (build 6) — stage release notes

Target: **stage** flavor / Neon stage branch. Previous build: 1.0.3+5.
Backend changes ship in the `laundry_pos` repo (branch `release/stage-1.0.4`); **deploy the backend first**.

## What's new (for testers)

**Dashboard**
- "Sales by date" and "Sales by service" each have their own period filter: **7 days**, the **current month** (e.g. "Oct 26", month-to-date), the **previous month** (e.g. "Sep 26"), or a **custom** date range (up to 366 days).
- The top cards now read **Sales today** and **Sales this month**.
- "How orders are moving" stays overall; "Collected vs Expenses" stays on the current month.
- Tap Open orders / Delivered / Due today to jump to Orders with that filter applied.
- New "Recent orders" card.

**Orders**
- Work status and Payment status dropdowns with an aligned Clear button; a period filter on the sales summary.
- Employees get quick filters (Late, Due today, Open, Delivered today).
- "In progress" now includes Ready orders, so the summary cards add up to the total.
- Search and filters reset when you switch outlet; searching with no match says so.

**Staff (owner)**
- Assign each employee to outlets (and a default) when adding or editing; the list updates immediately after saving.

**Sync and sign-in**
- A small floating bar shows syncing / offline / failed states without shifting the screen.
- Changes that could not be sent are shown (not silently dropped) and can be retried.
- Employees with several outlets sign in faster; switching outlet keeps the old outlet's data until the new one has loaded.
- If the session expires or outlet access is removed, the app now tells you instead of quietly showing old data.

## Fixes
- Staff list showed the old list for a few seconds after add/edit (server cache removed).
- Orders carried a filter over when the outlet changed (empty-looking list under "All").
- Search clear button is now a full 44 px tap target.
- Staff cards no longer wrap the phone number onto two lines.
- Sync banner could stay on "Fetching…" after a failed refresh.
- A retry after an interrupted order download restarts from where it stopped.
- Queued "deactivate/activate staff" can no longer overwrite a newer edit.

## Backend (laundry_pos)
- Employee outlet assignment validated (own, active outlets only).
- Invoice PDFs for employees limited to their own outlets (cross-outlet leak closed).
- Order idempotency checks outlet; status change row-locked (no double-apply race).
- `must_change_password` enforced; public error responses whitelisted; dashboard rollup span capped (92 days); calendar-range validation.
- `GET /employees` is no longer cached.
- No database migrations. New env needs: none (production must have `SESSION_SECRET`).
- `MOBILE_BLOCK_TERMS_NOT_SET` stays `false`.

## Known limitations (carry-over)
- Expenses cannot be edited or deleted yet (needs new backend routes).
- Not yet re-checked on a physical device: dashboard custom range, drill-down tiles, Recent orders, offline-then-sync pass.
- Login throttle is per server instance; `billing_pending` is not enforced server-side.
- No App Store / Play listing yet, so the force-update gate is dormant.

## Verification
- Mobile: `flutter analyze` clean, `flutter test` 800 passed.
- Backend: `tsc --noEmit` clean, 118 integration tests passed on a disposable local Postgres.
- Simulator passes (owner + three employee roles) ran against a local sandbox, not the shared database.

## Stage checklist
1. Deploy the backend branch to stage; confirm `SESSION_SECRET` is set.
2. Smoke the stage API: sign in as owner and employee, open Staff, add an employee, confirm the list updates immediately.
3. Build the stage app (below), install, sign in as owner, then as a multi-outlet employee.
4. Walk the tester items under "Known limitations" and record results in `docs/HANDOFF.md`.

## Build commands
```bash
flutter pub get
flutter build apk --release --flavor stage --dart-define=ENV=stage
flutter build ipa --release --flavor stage --dart-define=ENV=stage
```
Android output: `build/app/outputs/flutter-apk/`; iOS archive: `build/ios/ipa/`.
