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

## Current implementation and next work

The HTTP API and offline-ID sync work are implemented; mobile main includes PR #1 (`cdfc121`). Current context and batch status: `docs/HANDOFF.md`; durable rules: `docs/MEMORY.md`.

Flutter uses four work statuses (Pending, In progress, Ready, Delivered). Android/iOS are the targets. New web enhancements are tracked feature by feature in `docs/WEB-MOBILE-FEATURE-GAPS.md`, with offline regression checks. The audit does not mean those enhancements are implemented.

## Note

`.claude/launch.json` starts the **web** app (`npm --prefix
../laundry_pos run dev`) for design-parity checks. It is not used by the
Flutter build; delete it if you find it confusing.
