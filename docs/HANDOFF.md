# Session handoff — offline ids, syncing screen, local-first (2026-09-26)

Start here in a new (cloud) session. Local-only state — `~/.claude` memory,
`.wiki/` (gitignored), `.claude/CHECKPOINT.md` — is **not** available in the
cloud, so everything needed to continue is in this file and the docs it links.

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

- **Branch `frontend/offline-id`** (this repo) = `main` + docs + three
  committed batches, **not pushed, not merged**:
  - `32e7811` Phase 1 — two ids per order (`id` + `offlineId`), legacy
    `LOCAL-`/`OFF-` migration.
  - `dadee1d` Phase 2 — syncing (setup) screen after login and on
    never-synced outlets; remembered outlet across logout.
  - `14fb09d` Phase 3 — screens open from local data; network only on
    pull-to-refresh / Refresh / Sync now.
  - Gates at `14fb09d`: `flutter analyze` clean, `flutter test` **297/297**.
  Details, deviations and "as built" notes: `docs/OFFLINE-ID-SYNC-PLAN.md`.
- **Backend** `backend/offline-id` in `laundry_pos` carries the `offlineId`
  API (handled in a separate chat). Its migration is already applied to the
  Neon dev DB (checked with `prisma migrate status`).
- **Local testing setup:** app `ENV` defaults to `dev` → local backend at
  `127.0.0.1:3000` (iOS sim) / `10.0.2.2:3000` (Android emu). Start the
  backend with `npm run dev` in `../laundry_pos`. Flutter is not on the
  cloud image; this session used Flutter 3.47.5 cloned into the scratchpad.
- **Simulator check:** a Sonnet subagent ran a read-only pass of Phase 2 on
  the iPhone 17 Pro simulator (owner; the user signed in): fresh login,
  cold start, orders list and outlet switching all pass; the setup screen
  rows, a never-opened outlet and the employee flow were not seen. Details
  in the plan doc §8. Build command: `flutter build ios --simulator --debug
  --flavor dev --dart-define=ENV=dev` (bundle `com.myshop.myshop.dev`).
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
   the open empty-cache question; push `frontend/offline-id`; merge to `main`
   together with `backend/offline-id` when the user says so.
1. **Global outlet switcher in the app bar** (user request, verbatim:
   "make all outlets switch, need re-desing and show in app bar along with
   switch button — make it global state"). Today `OutletSwitcher`
   (`lib/shared/widgets/outlet_switcher.dart`) is embedded per screen:
   `owner_dashboard_screen.dart:267`, `owner_orders_screen.dart:473`,
   `orders_list_screen.dart:229`, `expenses_screen.dart:449`. Scope is already
   global via `OutletScopeCubit` (`lib/features/shell/bloc/`), provided in
   `main.dart`; refetch-on-switch lives in `main_navigation_shell.dart`.
   Wanted: one redesigned switcher (current outlet / "All outlets" + a switch
   button) in the shared app bar across tabs, replacing the per-screen
   copies. Brainstorm/confirm the design with the user first, then follow the
   Gemini workflow. Keep the employee rules: hidden for a single-outlet
   employee, no "All outlets" for employees.
2. Finish device tests: A9, A15/A16 (Ready violet — needs a real status
   change; ask first), A17 (collect dialog, don't submit), A18 (offline, two
   outlets → two bulk-sync calls), then Employee B1–B4 / C1–C3 and edge cases
   D1–D4 (need the user to sign in / set up accounts).
3. Fix batch for findings F1 (payment-method subtitle guesses "Cash" — new API
   has no `type`), then investigate F2–F4; F5 is backend, F6 is an owner
   decision.
4. Wiki last (local `.wiki/` already has `wiki/concepts/outlet-scope.md` as of
   2026-09-26; add anything durable from the tasks above).

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
