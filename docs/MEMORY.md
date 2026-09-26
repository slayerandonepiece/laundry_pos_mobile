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
  work the user asked Claude to implement.
- The user signs in on devices; never enter credentials.
- Owner add/edit forms are full-screen routes, never bottom sheets.
- UI says "Organization", never "Store", for the backend `Store` entity.
  In the user's own words "store" usually means **outlet**.
- Mobile only: no Flutter web (F0.4).
- Update this file, `docs/HANDOFF.md` and the relevant plan doc at the end of
  every session, and mention artifacts and discussions.

## Durable technical facts

- Order ids: `id` = server code `EL-<orderNumber>` (empty until synced);
  `offlineId` = app-generated UUID, unique per organization, null for web
  orders. See `docs/OFFLINE-ID-SYNC-PLAN.md` and backend
  `.agents/MOBILE-API-CONTRACT.md` §3.5.
- Local-first rule (user): every screen opens from local cache; network only
  on pull-to-refresh / Reload (plus background SyncEngine).
- Outlet facts: see "Durable knowledge" in `docs/HANDOFF.md`.
- Tests: use the Map-backed `FakeLocalCache` inside `testWidgets` (real Hive
  hangs under FakeAsync).
- Cloud sessions: Flutter is not preinstalled; download the stable SDK
  (3.47.x, Dart ≥ 3.13.1) into the scratchpad. Deleting remote branches is
  refused (HTTP 403) by the session git proxy — ask the user to delete them
  on GitHub.

## Artifacts

- Owner-screen wireframes (every owner screen, minimal UI):
  https://claude.ai/artifact/KXDqbi19o2crwHR9rw8to3
