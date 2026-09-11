# MyShop — laundry POS mobile app

Flutter app for the store workspace in `../laundry_pos`. "MyShop" is a
**working title**; it appears only on splash and login, never on
customer-facing output.

## Start here

| File | What it is |
| --- | --- |
| `prompts/README.md` | How the handoff works, and the design link |
| `TASKS.md` | Phase 2 — the Flutter build |
| `docs/DESIGN-SPEC.md` | Design tokens, metrics, navigation, screen inventory |
| `design/*.dc.html` | The artboards as plain HTML, one file per screen |
| `../laundry_pos/.agents/MOBILE-API-TASKS.md` | Phase 1 — the backend API |

## Approved designs

https://claude.ai/code/artifact/39d574e0-47c8-4b64-aa91-ae4a68d65b40

57 artboards. **v1 (48 screens, left) is approved. v2 (9 screens, far
right) is an exploration and needs sign-off before anyone builds it.**

## Phase 1 is not done

The backend currently has **no HTTP API** — no `src/app/api`, no bearer
auth, no middleware. The web app runs entirely on Server Actions, which
a Flutter client cannot call. Nothing in `TASKS.md` past F2 can start
until that is built.

## Open decisions

Four, listed in `TASKS.md` §F0. The blocking one: the database defines
three order statuses (`PENDING`, `IN_PROGRESS`, `COMPLETED`) but the
designs use four — `Ready` and `Delivered` do not exist yet.

## Note

`.claude/launch.json` starts the **web** app (`npm --prefix
../laundry_pos run dev`) for design-parity checks. It is not used by the
Flutter build; delete it if you find it confusing.
