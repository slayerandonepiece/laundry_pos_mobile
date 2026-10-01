# Project memory (committed, travels to cloud sessions)

Durable preferences and facts only. Task status lives in `docs/HANDOFF.md`;
plans live in their own docs. Native `~/.claude` memory and `.wiki/` are
machine-local and do **not** reach cloud sessions — this file does.

## How the user wants to work

- Never commit without explicit permission, per batch of work.
- Keep **one working branch per repo** using the user-requested name. Keep mobile and backend commits separate; inspect the actual main baseline before each batch.
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
  `--flavor dev` (bundle `com.reddygona.klenpos.dev`). Tell test agents
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

## KlenPOS rebrand, Firebase, and gating (28 September 2026)

- App is **KlenPOS**; bundle ID/applicationId `com.reddygona.klenpos`
  (`.dev`/`.staging` suffixes). Dart package name stays `myshop` —
  intentional, internal-only. Full detail: `docs/HANDOFF.md` "KlenPOS
  rebrand + Firebase + gating" section.
- Brand palette: Electric Cyan `#00D4FF`, Crisp Mint `#4CFFB3`, Deep
  Hydro `#0A2540`, Clean Obsidian `#0B0F14`. Source assets in
  `assets/icons/` and `assets/branding/`; see
  `assets/branding/klenpos_palette.md`.
- Native splash (Android `launch_background.xml`, iOS
  `LaunchScreen.storyboard`) is **white background + transparent logo
  only** — never a colored canvas. The in-app Flutter `SplashScreen`
  (`lib/features/auth/presentation/splash_screen.dart`) owns the actual
  Deep Hydro brand-color reveal. Don't reintroduce a colored native
  splash; it was explicitly reverted once already.
- Firebase (`lib/core/network/firebase_service.dart`): Crashlytics,
  Analytics, Messaging, Remote Config, initialized per dev/stage/prod
  flavor. Remote Config keys (`min_supported_version`,
  `force_update_enabled`, `maintenance_mode_enabled`, `ios_app_store_id`,
  `maintenance_message`, `maintenance_eta`) default to inert/empty in
  code — **not yet created in the Firebase console** for any of the 3
  projects. Nothing blocks the app until someone sets these remotely.
- Maintenance-mode + force-update gate: `lib/core/gate/app_gate_service.dart`
  (`lib/core/app_gate_service.dart` is a re-export, unused, harmless).
  Priority: maintenance mode > Android force-update (`in_app_update`,
  Play Core native flow) > iOS force-update (`upgrader`, non-dismissible
  via `canDismissDialog: false`/`showIgnore: false`/`showLater: false`).
  Checked at startup + app resume only, never per-route. Everything fails
  open on any error — only an explicit fetched "below minimum version"
  blocks. `ios_app_store_id` is empty until there's an actual App Store
  listing; `upgrader` no-ops gracefully until then.
- No App Store or Play Store listing exists yet — this whole gating
  system is dormant/inert by design until those exist and the Remote
  Config values are set.

## Artifacts

- Owner-screen wireframes (every owner screen, minimal UI):
  https://claude.ai/artifact/KXDqbi19o2crwHR9rw8to3

## Workspace enhancement rules (27 September 2026)

- Bring new web features/enhancements to Flutter feature by feature; retain mobile-only offline behavior. A source parity report is not implementation or device verification.
- Checkout methods are API/store-configured, in supplied order, with no synthetic pay-later method, Cash fallback or default preselection. COD detection uses normalized code first, then name (`COD` or `CASHONDELIVERY`); COD creates no initial payment.
- Catalog loads show cached products/methods immediately, then refresh enabled methods without losing the cache on failure. This is a deliberate freshness exception to cached screen navigation.
- Mobile password endpoints can rotate and return a token. Save it before later authenticated requests; owner change-password payload uses `oldPassword`, not `currentPassword`.
- Weighted full-height sheets need top safe-area protection with a keyboard; preserve their bottom keyboard/safe-area handling and scrollable content.
- Browser web-console checks use `localhost:3000`; the iOS API still uses `127.0.0.1:3000`. Do not classify non-localhost dev-asset failure or screenshot-pixel/device-point mismatch as an app bug.
- Never store account credentials in committed context, reports or memory. Keep historical test claims separate from fresh checks.

## Facts added 2026-10-01 (stage 1.0.4 prep)

- **Local sandbox for write testing**: a disposable local Postgres + backend on
  `http://127.0.0.1:3100` (owner + three employees with different outlet
  grants, two outlets, seeded orders/expenses). Build the app against it with
  `--flavor dev --dart-define=ENV=dev --dart-define=BASE_URL=http://127.0.0.1:3100`.
  Never write test data to the shared Neon DB; Neon access given is the
  **stage** branch only.
- `MOBILE_BLOCK_TERMS_NOT_SET` stays `false` (decided): an organization with
  no billing terms keeps working. Owners have no self-serve billing, so
  enabling it would lock them out.
- Dashboard card filters are per card, presets are 7 days / current month /
  previous month / custom (366-day cap); the default dashboard request is
  month-to-date. Do not reintroduce 30/90-day chips.
- A backend list cached with `unstable_cache` + `revalidateTag` can serve a
  stale first read after a write; mobile re-fetches right after saving, so
  such lists must not be cached (employee list was fixed this way).
- Date-dependent backend tests: the dashboard `cash` series covers the month so
  far, so assertions on its length must tolerate the 1st of a month.
- Simulator test agents lose screenshots to request limits; ask for few
  screenshots per step and treat unseen steps as unverified.
