# Session handoff — mobile workspace improvements (2026-09-28)

Start here in a new (cloud) session. Local-only state — `~/.claude` memory,
`.wiki/` (gitignored), `.claude/CHECKPOINT.md` — is **not** available in the
cloud, so everything needed to continue is in this file and the docs it links.

## Release observability and automation — 2 October 2026

- **A:** Added privacy-safe crash/session context with opaque user/store/outlet identifiers, uppercase role and environment; sign-out/block clears Crashlytics and Analytics identity.
- **B:** Added a no-throw analytics wrapper, environment-based collection, exact order/payment/invoice/sync/auth events, named pushed routes, and bottom-tab screen views.
- **C:** Added an injected dev/stage-only diagnostics dialog on version-label long press; production cannot open it.
- **D:** Stage arm64 R8 builds succeeded at each step. `classes.dex`: 3,721,848 bytes baseline; 3,177,968 without Flutter blanket keeps; 2,674,008 without the Firebase blanket keep. No missing-class warning was emitted. Re-measured with fresh A/B dev builds on 2 Oct: old rules 3,721,848 B (APK 22.80 MB) vs tightened 2,674,008 B (APK 22.41 MB). Logged-in release smoke test on the Pixel emulator passed (sign-in, dashboard, orders, order detail, Subscription, subscription invoice PDF; logcat free of ClassNotFound/NoSuchMethod/FATAL), so the tightened rules are kept.
- **E:** Added executable `scripts/release.sh` with guarded interactive/flag flows, external symbol retention, exact archive validation, and a side-effect-free stage dry run; README paths now point outside `build/`.

Focused tests, mutation checks, full analysis/tests, stage Android/iOS builds, and the final gate file record the verification evidence. No Firebase-console check or store upload was performed. Error handling: `runZonedGuarded` in `lib/core/error/error_reporting.dart` routes Flutter, platform and isolate errors to Crashlytics (non-debug only) with a friendly release ErrorWidget. The version label (`AppVersionText`: "Version 1.0.5 (8) · Stage") is on login and profile screens. iOS stage release build (obfuscated) succeeds, Runner.app 26.7 MB.

### Prod-readiness follow-up — 2 October 2026

- **API errors:** `DioLoggingInterceptor` now reports every failed API call (4xx, 5xx, timeouts, no-connection) to Crashlytics as a non-fatal (`FirebaseService.recordNonFatal`), with the real `err.stackTrace` and only `API <status or error type> <METHOD> <path>` (no query string, no body). Off in debug. Expect noise from offline use and expected 401/403/400 responses; they also stay in `NetworkHealth` and the breadcrumb log.
- **FCM token** is logged in debug builds only (release logs go to Crashlytics).
- iOS Firebase plists are per flavor in `ios/Firebase/{dev,stage,prod}/`. iOS dSYMs are uploaded automatically by the `[firebase_crashlytics] Upload Symbols` Xcode build phase (Release configurations, during Product > Archive).
- **Not verified:** no real fatal/non-fatal test from a prod build in the prod Firebase project, no Crashlytics alerts configured, and the prod flavor's Firebase/backend wiring was not exercised. Do these before the prod store release.

## Current status — 1 October 2026 (stage release 1.0.4+6 prep)

Supersedes the status sections below for anything they conflict with. Branch
`feat/dashboard-filters-and-sync-hardening` (from `main`) carries all of it. `flutter analyze`
clean, `flutter test` **800/800**. Backend (separate repo, branch `feat/outlet-access-hardening`):
`tsc` clean, 118/118 integration tests on a disposable local
Postgres. Device passes ran against a local sandbox only, never the shared DB.

### Done in this batch

- **Dashboard**: "Sales by date" and "Sales by service" each have their own
  period filter: 7 days, current month (month-to-date, e.g. "Oct 26"),
  previous month ("Sep 26"), custom range (366-day cap). "How orders are
  moving" stays overall; "Collected vs Expenses" stays on the current month.
  Headline pair is "Sales today" + "Sales this month". The default dashboard
  request/cache key is month-to-date (`mtd|scope`); a store switch reloads the
  same request. Tiles drill down to Orders (open / delivered today / due
  today); "Recent orders" card sorts by valid created dates only.
- **Orders**: Work/Payment dropdowns with an aligned Clear; summary period
  filter; employee quick filters; Ready counts under "In progress"; search and
  filters reset when the outlet changes; search-specific empty state; 44px
  search clear.
- **Staff**: outlet assignment on add/edit (`outlets` sent only when changed);
  one-line phone text; same helper copy on Add and Edit.
- **Sync/auth hardening**: resume guard, backfill of missing outlet caches,
  parallel employee sign-in, dead-letter banner, floating sync bar, poison
  batch splitting, truncated pull resumes from the last saved cursor, banner
  never stuck on "Fetching…", queued staff toggles replay only `active`,
  401/403 on reads propagate (network errors still use cache), logout parks
  unsynced queues under `parked_unsynced::<storeId>`.
- **Backend (separate repo)**: employee outlet assignment validated, invoice
  PDF routes check outlet access, idempotency + status races closed,
  `must_change_password` enforced, public-error whitelist, rollup span cap,
  `GET /employees` no longer cached (a fresh list right after a save).

### Working tree, 2 October (uncommitted in both repos)

Mobile `feat/expense-edit-and-switcher-fix`: analyze clean, 871 tests. Backend `feat/expense-routes-and-hardening-2`: tsc clean, 130 integration tests. Parity audit: `docs/PARITY-AUDIT-2026-10-01.md`.

Done from the audit (Batch A, mobile-only): access-403 queue safety (recoverable reasons stay queued; a bare 403 is still "outlet access changed"), 403 labels, staff password reset, per-outlet dashboard cards, dashboard polish, "This week" period chip (Monday to today, as on the web; replaces "7 days"), public invoice link ("Open in browser", final invoices only), plan/trial strip and silent `/auth/status` refresh on resume, must_change_password mid-session, neutral `billing_pending` copy, "Received now" partial payment at checkout, slab validation, Retry-After text on change-password. Verified on the iPhone 17 Pro simulator against the local sandbox: per-outlet cards (match the DB), Open-orders drill-down and totals, order search, resume refresh (trial strip and store-locked screen, both with no relaunch), part payment (₹15 of ₹40 stored), public invoice page opens, owner password reset (flag set, sessions revoked).

Skipped on purpose: PF-02 (the web has no "Organization contact" label) and OO-07 (needs the protected outlet switcher; audit lists it as deferred). Not started, needs backend endpoints first (Batch B): announcements, outlet directory/detail, read-only workspace for locked/lapsed stores, owner billing facts, real `passwordChangedAt`; B6 (an owner payment path for `billing_pending`) is a product decision. Not device-verified: expenses pull-to-refresh keeping a queued mark-paid (unit-tested), prepaid hand-over from Ready for an employee, EMP sign-in after the owner reset.

### Pending list

| # | Area | Pending |
|---|---|---|
| 1 | Expenses | **Done and committed (2 Oct)**: edit/delete (online only), chosen paid date, outlet attribution (E1–E3); backend routes added; queued changes survive refresh and Retry sends the queue. Device-checked on 1–2 Oct; the queued mark-paid refresh is unit-tested only |
| 2 | Device verification | Dashboard chips + custom range, Delivered/Due-today drill-down, Recent orders, pull-to-refresh, Part-paid filter combos, offline-then-sync pass, 401/403 propagation |
| 3 | Switcher | Menu-lingers glitch **not reproducible**; speculative fix reverted (showMenu returns at pop start, so it can't be proven). Employee landing in Lake is **by design** (remembered outlet wins). Monitor |
| 4 | Backend | **Done and committed in `../laundry_pos`**: DB-backed throttle, cookie carries token (one web re-login), per-tenant idempotency keys, `billing_pending` enforced behind the flag. Migration `20261001120000_…` NOT applied to Neon |
| 5 | Release | Deploy backend before stage mobile (employee-list change); `SESSION_SECRET` must be set in production (user manages it) |
| 8 | Parity gaps carried over | See "Parity gaps" under the 28 Sep status. Still open: no partial-access mode for `RESTRICTED` (a blocked 403 still shows `BlockedScreen`), no "Needs attention" list, billing card lacks plan/deposit/annual fee |
| 9 | Firebase and gating | Remote Config keys not created in the dev/stage/prod consoles; `AppGateService.isMidTransaction` not device-verified; Android `in_app_update` untested (needs a Play listing) |
| 10 | Backend/API gaps for the web team | No `/api/v1/outlets` route; no announcements endpoint; an employee omitting the outlet on rollups falls back silently instead of getting 403 |
| 6 | Store gating | No App Store listing yet, so `ios_app_store_id` and force-update stay dormant |
| 7 | Data | Neon has only a stage branch given to us; two old test employees ("Test Emp Single", "Test Emp Multi") remain there |
| 11 | Legal and privacy (3 Oct, not needed for first Play release; web items are in `../laundry_pos`) | (a) purge script/runbook for the "deleted within 3 months" promise: stores are only soft-deleted (`deletedAt`), nothing hard-deletes, and `Order`/`Payment` cascade from `Store`, so test on a throwaway store first; do this before real customer data is held; (b) `robots: noindex` and optional expiry on public invoice links `/i/[token]`; (c) record Terms/Privacy acceptance at onboarding (super-admin create-store); (d) cap on how long unpaid accounts stay on hold (now unlimited); (e) refund rule (Terms default: non-refundable); (f) web login still says MyShop/StoreOps, legal pages say KlenPOS; (g) website `[DOMAIN]` in `docs/legal/play-data-safety-answers.md`; (h) update policy and Play Data safety form when push notifications go live, a new SDK is added, or hosting region/retention changes |

Decisions taken 2026-10-01: `MOBILE_BLOCK_TERMS_NOT_SET` stays `false`
(unbilled organizations keep working; turning it on locks them out because
owners have no self-serve billing). Shared Neon DB = stage branch only.

## Current status — 28 September 2026 (KlenPOS rebrand + Firebase + gating)

This section supersedes the "28 September 2026" web/mobile parity section
below (that work is done and merged separately; this is a later, distinct
batch the same day).

Committed as `feb909f` on `feat/workspace-improvements`: `flutter analyze`
clean, `flutter test` **402/402** pass.

- **Rebrand**: app renamed MyShop → **KlenPOS**. Bundle ID / applicationId
  changed `com.myshop.myshop` → `com.reddygona.klenpos` (with `.dev`/`.staging`
  suffixes) across Android (`build.gradle.kts`, Kotlin package path) and iOS
  (`project.pbxproj`, all schemes). Dart package name (`myshop` in
  `pubspec.yaml`) was **left unchanged** — it's an internal identifier, not
  user-facing, and renaming it would touch every import for no user benefit.
  Brand palette: Electric Cyan `#00D4FF`, Crisp Mint `#4CFFB3`, Deep Hydro
  `#0A2540`, Clean Obsidian `#0B0F14` (see `assets/branding/klenpos_palette.md`).
- **App icon & splash assets**: final set in `assets/icons/` and
  `assets/branding/` (iOS 1024 no-alpha icon, Android adaptive
  foreground/background layers, Play Store/feature-graphic assets, logo
  lockups, favicons). Wired into `ios/Runner/Assets.xcassets/AppIcon.appiconset`
  and Android `mipmap-*` via `sips` (see `docs/BRANDING-AND-FIREBASE-SETUP.md`).
  **Native splash is white background + the transparent
  `klenpos_adaptive_foreground_432.png` logo only** — not a colored canvas;
  an earlier colored-background version was explicitly reverted per user
  request, and the two now-orphaned colored splash PNGs
  (`klenpos_splash_android.png` / `klenpos_splash_ios.png`) were deleted
  before this commit, never having been in history. The in-app Flutter
  `SplashScreen` (not the native one) owns the actual Deep Hydro brand-color
  experience, with a circular logo and an animated background reveal —
  see `lib/features/auth/presentation/splash_screen.dart` and
  `test/widgets/splash_screen_test.dart`.
- **Firebase**: `lib/core/network/firebase_service.dart` initializes Core,
  Crashlytics (disabled in debug), Analytics, Messaging, and Remote Config,
  gated per dev/stage/prod flavor. Remote Config `setDefaults()` are
  deliberately inert/empty (`min_supported_version: ""`,
  `force_update_enabled: false`, `maintenance_mode_enabled: false`,
  `ios_app_store_id: ""`) so nothing blocks the app until these are set in
  each Firebase project's console — **not yet done**, no App Store/Play
  Store listing exists yet either, so `ios_app_store_id` stays empty until
  there's something to point it at.
- **Maintenance mode + force update**: `lib/core/gate/app_gate_service.dart`
  (`lib/core/app_gate_service.dart` is a thin re-export, kept for import
  convenience but currently unused — harmless, not wired anywhere) evaluates,
  in order: maintenance mode (highest priority, custom full-screen
  `lib/features/maintenance/presentation/maintenance_screen.dart`) → Android
  force update (`in_app_update` package, Play Core native immediate-update
  flow) → iOS force update (`upgrader` package, non-dismissible alert via
  `canDismissDialog: false` / `showIgnore: false` / `showLater: false`,
  redirects to the App Store product page). Checked at startup and on app
  resume from background (not on every route — this is a POS app, staff
  leave it open all day; per-route checks would also risk interrupting a
  live transaction). **Everything fails open** on any fetch/lookup/version-
  parse error — Remote Config being unreachable, offline, or a sideloaded
  dev/stage build never blocks the user, only an explicit successfully-
  fetched "you're below minimum version" result does.
- **Still open / not yet done**: Firebase Remote Config keys not yet created
  in the 3 Firebase project consoles (dev/stage/prod); `ios_app_store_id`
  and store URLs unset (no store listings yet); resume-check's
  mid-transaction deferral (`AppGateService.isMidTransaction`) exists but
  hasn't been independently device-verified; Android `in_app_update` flow
  not yet tested against an actual Play Store internal-testing track (only
  reachable once there's a Play Console listing).

## Current status — 28 September 2026

This section supersedes the 27 September section below, which is itself now
historical (its own "Next work" item 2 predicted exactly this batch — web
enhancement parity — so treat this as that work starting, not a new
direction).

### Web/mobile feature-parity audit

Codex independently audited `../laundry_pos` (web, source of truth): all ten
admin modules, 199 source-cited capability bullets, live browser/API
verification, 89/89 integration tests passing. Artifacts in
`../laundry_pos/audit/`. Five parallel Claude agents then cross-checked every
bullet against this repo's actual Dart source (bloc → event → repository →
API-client chains, not just filenames), classifying each as
Implemented/Partial/Missing/Intentionally-different/N-A-for-mobile, and
separately listing web-only defects not to copy into mobile. Full detail:
local `.wiki/raw/notes/2026-09-28-web-mobile-parity-audit-and-fixes.md`
(gitignored — this section is the cloud-visible summary).

### Fixed and verified this batch (`flutter analyze` clean, `flutter test`
**374/374** pass at the time of each verification)

- **Payment/delivery decoupling** (the original complaint): payment collection
  was hard-coupled to marking an order Delivered (`CollectPaymentDialog`
  always paid the full balance and delivered in one step; no way to record a
  partial payment or deliver with a balance due). Added `RecordPaymentEvent`
  (standalone payment, any amount up to balance, any status, no status
  change) + `record_payment_dialog.dart`; added `Delivered` to
  `status_dialog.dart`'s status list with a "deliver anyway" confirmation when
  a balance remains (dispatches the existing `HandoverOrderEvent`, which never
  actually checked balance — it just wasn't reachable with money owed before).
  The original combined "Collect payment & deliver" flow is untouched, kept as
  a shortcut.
- **Checkout**: removed hardcoded payment-option subtitles ("Collect full
  amount at handover"/"Pay full amount now"); added a real due-date picker
  (default changed from hardcoded +2 days to today, rejects past dates) and an
  optional notes field — both fields already existed on `Order`/already
  accepted by the create-order API, just never exposed in the UI.
- **Payment methods**: disabling a method now shows a confirm dialog
  ("Disable {name}? Customers will no longer be able to pay with {name}...",
  reusing the existing `CentredDialog`); enabling stays instant.
- **Invoice PDF**: rebuilt `order_pdf_builder.dart` to match web's
  `OrderInvoicePdf.tsx` structure — added order/delivery dates, a Rate column
  ("Slab pricing" for weight lines), a Payment summary, a per-payment
  "Payments received" table (previously only an aggregate total), and the
  "not a tax invoice" footer. Stayed client-side/offline-capable by design —
  `getInvoicePdfBytes` (server-rendered PDF) remains intentionally unused.
  Paired backend change: `../laundry_pos` now returns `invoice.generatedAt` on
  the Order DTO (additive; covered by an extended B6.5 assertion, 89/89 still
  pass) so the PDF footer date is accurate instead of always "now".
- **BlockedScreen**: added `onRetry` (wired to the existing
  `CheckAuthStatusEvent` — accepted a brief splash-screen flash rather than
  adding a new bloc state) and `pendingCount` (from
  `LocalCacheService.getTotalPendingCount()`) so a user isn't stuck with only
  "Sign out" and no visibility into whether queued offline writes are safe
  (they are — `SyncEngine` keeps retrying them in the background regardless of
  block state, it just wasn't visible).
- **Trial/subscription banner data plumbing**: backend's `getStoreAccessStatus`
  already computed `trialEndsAt`/`subscriptionState` live per-request (a
  renewal payment is reflected on the very next request, no caching) but only
  attached them to the `organizations[]` array, not the `stores[]` array
  mobile actually parses. Backend now mirrors both onto `stores[]`; mobile's
  `StoreSummary` parses them and `more_screen.dart`/`subscription_screen.dart`
  branch the renewal badge on actual state (TRIAL/TRIAL_ENDING/
  SUBSCRIPTION_ENDING/ACTIVE) instead of one flat "paidThroughDate <= 7 days"
  heuristic that couldn't tell a trial ending from a paid plan ending.
  **Implemented but not yet independently re-verified this session** — do that
  before treating it as done. Plan name/deposit/annual-fee display is still
  missing from the billing card; this fix only addressed trial/renewal state.

### Confirmed open — not yet fixed, not yet prompted

- Subscription lockdown is still all-or-nothing: any blocked-reason 403
  replaces the whole app via `BlockedScreen`. Web keeps historical reads
  (orders/invoices/rollups) working during a `RESTRICTED` subscription state;
  mobile has no partial-access mode. The BlockedScreen fix above is a smaller
  companion, not this.
- Staff editor has no outlet (re)assignment (joint gap — the mobile API
  contract itself doesn't carry outlet fields on `/employees` yet either) or
  password-reset (pure mobile gap — `PUT /api/v1/employees/{id}` already
  accepts a password field server-side).
- Dashboard missing: all-outlet per-branch cards, "Needs attention" combined
  overdue/due-today list, general empty state. **Updated 1 Oct:** the
  recent-orders list and tile drill-down now exist, and the "Last 14 days"
  default is superseded by the month-to-date default.
- No read-only outlet/branch directory on mobile at all (distinct from the
  outlet-scope switcher) — largely blocked by no `/api/v1/outlets` route
  server-side (mobile only ever gets bare `allowedOutlets[]`: id/code/name/
  status, no address/opened-date/staff/chart data).
- Product editor's slab-limit validation is looser than web (silently sorts
  non-increasing limits instead of rejecting).
- No proactive session/subscription refresh on app resume, only on cold start
  or reactively on a 403 (`AppResumeSync` only triggers order sync).

### Backend/API gaps — flag to the web team, not mobile tasks

- Expense edit/delete/backdated-pay have no REST endpoint (web-only Next.js
  server actions).
- No `/api/v1/outlets` list/detail route.
- Rollups endpoint lets an employee omit outlet and silently falls back
  instead of the documented 403.
- **Security-relevant, worth prioritizing independent of mobile's schedule**:
  an employee can currently fetch another outlet's invoice PDF via
  `/invoice/pdf` with no outlet-membership check.
- No mobile-facing announcements endpoint exists at all.

### Confirmed fine — don't "fix" these chasing parity

- Login body `{phone,password}` matches the contract exactly.
- Offline-first caching/idempotency/bulk-sync batching — don't simplify to
  match web's simpler model.
- Mobile's checkout already avoids a real web bug (COD pre-selected, so a
  positive amount charges even when COD is picked) — don't copy that in.
- Mobile's strict 10-digit Indian-mobile phone regex is correct as-is; web's
  looser 8-15-digit rule is the actual bug, for an India-only business.
- Mobile already forces the mandatory first-login password change; web has a
  known enforcement gap here, mobile is stricter/correct.

## Historical: current status — 27 September 2026

This section formerly superseded the branch/test-status notes below it; it is
now itself historical, superseded by 28 September above.

### Repository baseline and this batch

- Mobile `main` is `cdfc121d2f34bdc301c05f95a6feb0ad3b876c13`, Merge pull request #1 from `slayerandonepiece/frontend/offline-id` (26 September). Offline-ID phases, bootstrap/local-first flow, outlet handling and consistency fixes from that branch are merged. The older “pushed, not merged” statements below are historical.
- User authorized including all current mobile changes from Claude/Gemini/GPT on `feat/workspace-improvements`. This batch remains separate from `laundry_pos`; no backend changes are committed here.
- Claude chat reviewed: **Pending mobile app test cases** (local mobile project). Its latest commit/push attempt stopped at a session limit. Git inspection confirms today's files were still uncommitted on main before this batch. Visible conversations are context, not independent proof of their test claims.
- GPT authored `docs/WEB-MOBILE-FEATURE-GAPS.md`: feature-by-feature source audit with 68 pending acceptance checks (60 open, 8 ticked as of 1 Oct 2026), including eight offline regression checks. This is a plan/checklist, not implemented web parity. GPT made no application-code changes during that audit.

### Changes included from the working tree

- Username → phone login/model/staff payload alignment; account/contact display updates and matching test fixtures.
- Password setup retains the API's rotated token; owner password change sends `oldPassword` and retains its returned token.
- Staff creation sends `active: true`.
- Checkout options come from enabled store methods. Real COD submits no initial payment; no synthetic pay-later option or invented Cash fallback. No enabled COD means no pay-later choice. Cached methods are emitted first, then refreshed with cache retained on failure.
- Keyboard/safe-area/layout improvements in weighted/item dialogs, shared buttons/scaffold/bottom navigation, invoice sheets and forms; weighted sheet uses `useSafeArea: true`.
- Owner shell refreshes dashboard/expenses on store switch and expenses on opening More, addressing stale overview badges.
- New tests cover password-token/API behavior, configured checkout methods/COD and weighted-sheet safe area. Manual run and outstanding cases are recorded in `docs/E2E-MANUAL-TEST.md` and `docs/MANUAL-TEST-CASES.md`.

### Verification and limits

- Current batch: `flutter analyze` passed, no issues (27 September).
- Current batch: `flutter test --reporter expanded` passed all **333 tests** (27 September); `git diff --check` passed. Historical counts below describe older snapshots. Logs for this run: `/private/tmp/laundry-mobile-analyze.log` and `/private/tmp/laundry-mobile-tests.log`.
- Earlier GPT launch check: iPhone 17 Pro dev build launched, auth/status and order delta returned 200 and sync completed. GPT did not visually verify the app screen; its computer-use tool could not bind Simulator. Android Pixel 9 disconnected before app launch.
- Claude's manual test document contains pass/view-only/pending/blocked results. Do not convert view-only or older blocker entries to completed workflows. X10/X12/X14 were later withdrawn as origin/input-tooling artifacts; preserve that correction.
- Test-environment cleanup in the manual documents remains a follow-up: historical notes report a trial organization temporarily unlocked and an employee intentionally inactive. Their current state has not been rechecked in this batch. Do not change shared state without user authorization.

### Next work

1. Complete the manual checks that remain applicable, especially configured-method refresh, COD, weighted dialog with keyboard, employee flows and offline replay.
2. Implement web enhancement parity only after a scoped plan: dashboard metric semantics/cards/drill-down, expenses edit/delete/paid-date/attribution, staff assignments/reset, outlet views, richer profile facts, trial/lock/announcement notices.
3. Preserve mobile offline identities, caches, scoped queues, idempotent replay, reconnect/resume and local PDF sharing. Avoid replacing repositories with web fetching patterns.
4. Check backend endpoint readiness before native controls: announcements, locked reads, expense mutations/paid date and full profile/outlet facts have API gaps.
5. No new parity feature is implemented merely because its checkbox exists; device acceptance stays pending until actually observed.

## Read first, in this order

1. `CLAUDE.md` — scope boundary (surgical changes, no opportunistic refactors).
2. `docs/MEMORY.md` — the user's working preferences and durable facts.
3. `docs/OFFLINE-ID-SYNC-PLAN.md` — **current task**: findings, plan, status.
4. `../laundry_pos/.agents/MOBILE-API-CONTRACT.md` — backend repo
   `slayerandonepiece/laundry_pos`, working branch `backend/offline-id`
   (§3.5 = the new `offlineId` contract). Generated from server code;
   **it wins** wherever it disagrees with the spec.
5. `docs/OUTLET-PARITY-SPEC.md` — client plan (O0–O11). O7 already rewritten
   to match the contract.
6. `docs/OUTLET-DEVICE-TEST.md` — live device-test checklist + findings F1–F6.

## Standing rules from the user (keep following them)

- **Workflow:** Graft (trace code) → relevant Memory/Wiki → complete
  ("UnLazy") Gemini prompt → Gemini implements → Claude verifies independently
  → selectively update durable knowledge. Claude implements directly **only
  when explicitly asked**. Gemini prompts: one chat code block, file-and-line
  precise, with their own verification commands. Never trust a Gemini report —
  re-check `git status`, the diff, `flutter analyze`, `flutter test`, and a
  device check for UI.
- **Never commit without explicit permission**, per batch of work.
- Run commands yourself (don't hand the user commands to paste) unless the
  action is destructive/irreversible.
- Memory/Wiki: selective, durable facts only; never branch/commit/task status
  in the Wiki. Memory hooks stay off. The Wiki update is done **last**.
- "Check edge cases / related files" = inspect, not modify.
- Staging DB (`laundry_pos` `.env` `DATABASE_URL`, Neon) is additive-only
  unless the user explicitly asks for a reset; they run resets themselves.
- The user signs in on devices themselves — never enter credentials.
- Don't toggle org payment methods or other shared config without asking;
  confirm before irreversible actions (placing orders, recording payments,
  status changes on real orders).
- Owner add/edit forms are full-screen routes with proper scrolling, never
  bottom sheets.
- Web Super Admin UI says "Organization", never "Store" (internal `Store`
  identifiers stay).

## Where things stand (updated end of 2026-09-26 app session)

- **Branch `frontend/offline-id`** (this repo) = `main` + docs + these
  commits, **pushed, not merged**:
  - `32e7811` Phase 1 — two ids per order (`id` + `offlineId`), legacy
    `LOCAL-`/`OFF-` migration.
  - `dadee1d` Phase 2 — syncing (setup) screen after login and on
    never-synced outlets; remembered outlet across logout.
  - `14fb09d` Phase 3 — screens open from local data; network only on
    pull-to-refresh / Refresh / Sync now.
  - `a753d64` device findings F1, F2, F4 fixed (Gemini, verified).
  - `74d6e40` app audit fixes (Gemini, verified): owner screens show a
    first-load spinner and errors; pull-to-refresh waits for the result;
    dashboard pull/Refresh also syncs orders; sync on app resume
    (`lib/core/sync/app_resume_sync.dart`); staff can only be added online
    (no password stored in the offline queue); a queued "mark paid" /
    staff edit keeps the server id across sync runs.
  - Consistency batch (Gemini, verified): owner writes match the backend
    (PUT profile/employees, explicit staff active, `POST /products`),
    idempotency keys for expense/staff create, per-screen owner
    loading/errors, "Can't load orders", order-detail saved-copy message,
    F3 test, and the outlet switcher as the app bar title (Option C).
    See plan doc §10.
  - Gates now: `flutter analyze` clean, `flutter test` **320/320**.
  Details, deviations and "as built" notes: `docs/OFFLINE-ID-SYNC-PLAN.md`
  (§8 verification log, §9 audit).
- **Backend** `backend/offline-id` in `laundry_pos` carries the `offlineId`
  API (handled in a separate chat), plus idempotent `POST /expenses` and
  `POST /employees` by `idempotencyKey` (migration
  `20260926120000_add_expense_and_staff_idempotency_key`). All migrations
  are applied to the Neon dev DB; backend tests 57/57.
- **Local testing setup:** app `ENV` defaults to `dev` → local backend at
  `127.0.0.1:3000` (iOS sim) / `10.0.2.2:3000` (Android emu). Start the
  backend with `npm run dev` in `../laundry_pos`. Flutter is not on the
  cloud image; this session used Flutter 3.47.5 cloned into the scratchpad.
- **Simulator check:** a Sonnet subagent ran a read-only pass of Phase 2 on
  the iPhone 17 Pro simulator (owner; the user signed in): fresh login,
  cold start, orders list and outlet switching all pass; the setup screen
  rows, a never-opened outlet and the employee flow were not seen. Details
  in the plan doc §8. Build command: `flutter build ios --simulator --debug
  --flavor dev --dart-define=ENV=dev` (bundle `com.reddygona.klenpos.dev`).
- Superseded branch `claude/nifty-newton-8w8fhh` and the merged
  `chore/backend-and-setup` branches (both repos) are for the user to delete
  on GitHub (session git proxy refuses remote deletes).
- **Artifacts:** owner-screen wireframes (every owner screen, minimal UI) —
  https://claude.ai/artifact/KXDqbi19o2crwHR9rw8to3
- **Discussions this session:**
  - User approved each batch and its commit separately.
  - Pending decisions resolved with the recommendations: web order's
    `offlineId` stays on the phone; services & prices are one setup row.
  - User asked to run the app against local/dev (localhost); confirmed no
    config change needed.
  - User wants testing delegated to Sonnet ("opus is not required").
  - Open, told to the user: a screen with nothing cached fetches once (as
    built) vs strict empty state + Reload.
  - Later the same day the user asked for an app audit (pull-to-refresh,
    which screens call the API on open, retries, duplicates, errors). The
    findings are in the plan doc §9. Fixes went through the Gemini workflow:
    Claude wrote the prompts
    and re-verified, including removing a fix to prove its test fails
    (caught one test that proved nothing, and a double-SnackBar regression
    Gemini introduced; both fixed before commit).
- Earlier discussions (still valid): F0 answered (`TASKS.md`); "store" =
  outlet; one working branch per repo; merge to `main` (no auto-deploy).

### Earlier state (outlet parity)

- Spec O11 steps 1–10 + contract gaps 1–3 implemented; `flutter analyze`
  clean; `flutter test` **273/273** pass.
- Device test (iPhone 17 Pro simulator, dev flavor, local backend
  `npm run dev` in `../laundry_pos` on :3000): Owner A1–A8, A10–A14 pass —
  see the log. A9 was mid-run (`12345` typed, not yet blurred).

## Next tasks (in order)

0. **Finish offline ids / sync screen / local-first** — code done
   (`docs/OFFLINE-ID-SYNC-PLAN.md`). Left: simulator check of Phase 1
   (`OFF-` codes, create/pay offline then sync — needs the user's OK since it
   creates real orders) and Phase 3 (screens open without network); answer
   the open empty-cache question; merge to `main` together with
   `backend/offline-id` when the user says so. Also simulator-check the
   `74d6e40` fixes (owner spinner/errors, pull spinner, resume sync) and
   the consistency batch against the real backend (store profile, staff
   edit/active, add/edit service, add expense/staff twice → one row).
1. ~~Global outlet switcher in the app bar~~ — done (Option C, plan doc
   §10). Simulator-check it: owner menu, employee with 1 and 2 outlets,
   offline + outlet not on this phone.
2. Finish device tests: A9, A15/A16 (Ready violet — needs a real status
   change; ask first), A17 (collect dialog, don't submit), A18 (offline, two
   outlets → two bulk-sync calls), then Employee B1–B4 / C1–C3 and edge cases
   D1–D4 (need the user to sign in / set up accounts).
3. F1–F4 done (F3 covered by a test). Left: F5 is backend (watch); F6 is
   an owner decision. Audit leftovers (plan doc §9) are all fixed (§10).
4. Wiki last (local `.wiki/` already has `wiki/concepts/outlet-scope.md` as of
   2026-09-26; add anything durable from the tasks above).

## Status — 2 Oct 2026 (end of day)

Branch `feat/expense-edit-and-switcher-fix` (mobile) and `feat/expense-routes-and-hardening-2` (backend `../laundry_pos`). Neon stage migration `20261001120000_hardening_2_...` is applied and verified. Full gate: `dart format .`, `flutter analyze` clean, 880 tests.

Done this round:
- Dashboard: "This week" (Mon–today) replaces "7 days"; Sales by date opens on This week; Compare removed; per-outlet cards, expenses headline, needs-attention, first-use card removed; auto-reload when orders change; a one-day chart starts at zero.
- Payments: Record payment is a method picker for the full balance (no typing), locked to the method already used, never Cash on Delivery. Checkout: due-date chips, methods two per row, Cash on Delivery as its own button, back returns to the items, X asks to discard. Activity & history is inline on the order page.
- Invoices: in-app View renders the real PDF, laid out like the web invoice; public web invoice page shows the invoice first and full width with small Print/Download below. Owner Subscription screen lists subscription invoices and opens each as a PDF (new backend routes, see `.agents/MOBILE-API-CONTRACT.md`).
- Build: unused assets and `cupertino_icons` dropped; Android res images are lossless WebP; plain HTTP is dev-flavor only (manifest overlay + Dart HTTPS rule); a stage/prod flavor can never resolve to dev; `allowBackup="false"`. Prod arm64 APK about 22.5 MB, iOS Runner.app about 27 MB.

Open (in order):
1. 401/403 data-loss edge case (section below) — not done.
2. Encrypt the Hive cache (AES cipher, key in secure storage, one-time migration for existing installs).
3. Play Console follow-ups: review the pre-launch report, declare analytics/crash data in the Data safety form and iOS PrivacyInfo, and confirm testers are opted in so the internal-track update appears.
4. Batch B (needs new backend endpoints first): announcements, outlet directory/detail, read-only workspace for locked/lapsed stores, owner billing facts, passwordChangedAt; plus the owner payment path for `billing_pending` (a product decision).
5. Not yet seen on a device: queued mark-paid staying Paid after refresh; employee hand-over of a prepaid order from Ready; employee sign-in after an owner password reset.
6. Optional: a pink "previous period" line on the chart (no button), an "Organization-wide" outlet bucket (needs the protected outlet switcher file), `Renews on 2100-01-01` shows a raw ISO date on Subscription.

## Open: unsynced data and auth failures (2026-10-02, owner's request)

Edge case to solve, not done yet. When a 401 (or a reason-less 403) arrives
while changes are still queued, `AuthRepository.logout(involuntary: true)`
signs out, wipes the local cache, then writes the queues back under
`parked_unsynced::<storeId>`. Data is lost if the app is killed between the
wipe and that write, if the write fails, or if the person signs in somewhere
the parked copy is not restored. A token that expires while the app is closed
hits the same path on next launch.

Rule to implement: whatever the user does is saved locally first, then synced
in the background; the UI never waits for the API.
- On 401/403, do not wipe. Keep local data and the outbox, show "sign in
  again" over the app, resume sync after sign-in.
- Wipe only on a deliberate sign-out, and only when the outbox and dead-letter
  lists are empty, or the person confirms losing them.
- Move the parking write before any wipe (or drop parking entirely), and make
  it atomic.
- Audit the remaining direct API calls (profile, change password, customer
  lookup, owner actions) and move any user-visible write onto the outbox.
- Tests: kill-between-steps, parking write failing, different user signing in.

## Durable knowledge (mirror of the local Wiki article)

- Outlet id: `X-Outlet-Id` header, else `?outletId=`; `/api/v1/dashboard`
  reads **only** `?outletId=`. Employees must send an outlet on
  orders/sync/bulk-sync (403 otherwise); owners may omit (= whole org).
- `bulk-sync` rejects a `create_order` whose `payload.outletId` differs from
  the request outlet → client sends one request per outlet group; a 403
  dead-letters only that group. `kNoOutletHeader = '__no_outlet__'` makes the
  interceptor omit the header.
- `/auth/login` and `/auth/status` both return
  `organizations[].allowedOutlets`; cached by
  `AuthRepository._cacheOrganizationOutlets`.
- Outlet loss (reason-less 403 or 400 "Invalid outlet.") →
  `main.dart _handleOutletAccessLost()`: refresh `/auth/status`; re-prompt
  only if the old outlet is gone, else sign in again (no loop).
- Cache keys for orders, sync cursor, dashboard metrics, expenses are
  outlet-scoped (`base::storeId::(outletId|all|none)`).
- Payment methods are organization-level `{id, code, name, enabled}`;
  `?all=true` includes disabled; owners only toggle (`PATCH {'enabled'}`);
  create = 410. Never pre-select a method.
- Ready = violet (`AppColors.violet`); amber `PillVariant.warning` = payment/due.
- Tests: never real Hive inside `testWidgets` when code writes to it (hangs
  under FakeAsync) — use a Map-backed `FakeLocalCache`. Override every new
  `LocalCacheService` getter in fakes. Widgets watching `OutletScopeCubit`
  need it provided in tests.
