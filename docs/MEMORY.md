# Project memory (committed, travels to cloud sessions)

Durable preferences and facts only. Task status lives in `docs/HANDOFF.md`;
plans live in their own docs. Native `~/.claude` memory and `.wiki/` are
machine-local and do **not** reach cloud sessions — this file does.

## How the user wants to work

- Never commit without explicit permission, per batch of work.
- Keep **one working branch per repo, named per side**: `frontend/offline-id`
  here, `backend/offline-id` in `laundry_pos`. Pull `main` into it before
  each batch.
- Frontend and backend work happen in **separate chats**, each with its own
  prompt and its own diff — never club the two repos in one session or diff.
- Merge finished work to `main`; merging does not deploy (auto-deploy
  disabled by the user).
- Run commands yourself; confirm before irreversible actions (real orders,
  payments, status changes, shared config, deleting data/branches).
- Surgical changes only (`CLAUDE.md`). Plan first, ask when unclear.
- Workflow option from `HANDOFF.md`: Claude writes Gemini prompts and
  verifies; Claude implements directly only when asked — for the offline-id
  phases the user asked Claude to implement; the later fix batches went
  through Gemini. When verifying, remove the fix and confirm the new test
  fails — a Gemini test once passed without the fix.
- The user signs in on devices; never enter credentials.
- Owner add/edit forms are full-screen routes, never bottom sheets.
- UI says "Organization", never "Store", for the backend `Store` entity.
  In the user's own words "store" usually means **outlet**.
- Mobile only: no Flutter web (F0.4).
- Delegate simulator/device testing to a **Sonnet** subagent — Opus is not
  needed for testing (user, 2026-09-26). Testing is read-only unless the user
  approves real orders/payments/status changes; the user signs in.
- Test against the local backend: the app's default `ENV=dev` already points
  to `127.0.0.1:3000` (iOS sim) / `10.0.2.2:3000` (Android emu); run the
  backend with `npm run dev` in `../laundry_pos`. iOS builds need
  `--flavor dev` (bundle `com.myshop.myshop.dev`). Tell test agents
  whether signing out is allowed.
- Update this file, `docs/HANDOFF.md` and the relevant plan doc at the end of
  every session, and mention artifacts and discussions.

## Durable technical facts

- Order ids: `id` = server code `EL-<orderNumber>` (empty until synced);
  `offlineId` = app-generated UUID, unique per organization, null for web
  orders. See `docs/OFFLINE-ID-SYNC-PLAN.md` and backend
  `.agents/MOBILE-API-CONTRACT.md` §3.5.
- Local-first rule (user): every screen opens from local cache; network only
  on pull-to-refresh / Reload (plus background SyncEngine). In code: owner
  `Load*` events read cache unless `refresh: true`; nothing cached yet →
  fetched once. Dashboard caches only the default period.
- Setup (syncing) screen shows on fresh login and whenever the active outlet
  scope has no cached order list (`main.dart _needsSetup`); an empty list
  `[]` means "set up, no orders".
- Employee outlet choice is remembered per user + organization under
  `remembered_outlet::<userId>::<storeId>`; `LocalCacheService.clear()`
  (logout) keeps those keys.
- Outlet facts: see "Durable knowledge" in `docs/HANDOFF.md`.
- Owner `Load*` events take an optional `Completer<void> done` that the
  bloc always completes; pull-to-refresh awaits it. Owner screens show
  `OwnerState.error` in a SnackBar; the dashboard (kept alive in the
  shell's `IndexedStack`) shows errors only while its route is on top, to
  avoid duplicate SnackBars.
- Staff can only be added online — never queue a staff password locally.
  Expense and staff creation send an `idempotencyKey` generated once per
  form (backend dedupes by it); a queued expense replays with the same key.
  Products are saved with `POST /products` (upsert by a client id chosen
  once per form). Staff active/inactive is an explicit `PUT /employees/{id}`
  (`set_staff_active`), never the flipping `toggle-active` endpoint.
- `OwnerState` has per-screen `loading` (`Set<OwnerSection>`) and
  `messageSection`; each owner screen shows only its own spinner and
  SnackBars.
- The outlet switcher is the app bar title (`OutletTitleSwitcher`, design
  "Option C") on Dashboard, both Orders screens and Expenses; the old
  in-body `OutletSwitcher` is deleted. Offline, an outlet whose orders
  aren't cached can't be picked (SnackBar).
- The app syncs on resume (`AppResumeSync` in `main.dart`, uses
  `SyncEngine.trigger()`).
- Tests: use the Map-backed `FakeLocalCache` inside `testWidgets` (real Hive
  hangs under FakeAsync). Fakes that extend `LocalCacheService` must override
  every new cache method they reach (else "Box not found"); stubs that
  `implements` a repository must override every new method they reach
  (else NoSuchMethodError). A `MyShopApp` test needs a cached order list or
  it opens the setup screen.
- Cloud sessions: Flutter is not preinstalled; download the stable SDK
  (3.47.x, Dart ≥ 3.13.1) into the scratchpad. Deleting remote branches is
  refused (HTTP 403) by the session git proxy — ask the user to delete them
  on GitHub.

## Artifacts

- Owner-screen wireframes (every owner screen, minimal UI):
  https://claude.ai/artifact/KXDqbi19o2crwHR9rw8to3
