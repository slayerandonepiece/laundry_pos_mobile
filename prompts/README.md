# Handoff prompts

Two phases, in order. **Phase 1 must be complete before Phase 2 starts** —
as of 2026-09-11 the backend exposes no HTTP API at all, so there is
nothing for the Flutter app to call.

| Phase | Prompt | Task list | Repo |
| --- | --- | --- | --- |
| 1 · Backend API | `01-backend-api.md` | `../../laundry_pos/.agents/MOBILE-API-TASKS.md` | `laundry_pos` |
| 2 · Flutter app | `02-flutter-app.md` | `../TASKS.md` | `laundry_pos_mobile` |

## Approved designs

**https://claude.ai/code/artifact/39d574e0-47c8-4b64-aa91-ae4a68d65b40**

Shared with anyone who has the link. 57 artboards on a pan/zoom canvas.

- **Left / main body — v1, 48 screens. This is the approved set.**
- **Far right (x ≈ 4000) — v2, 9 screens. An exploration. Do NOT build
  it without explicit sign-off.**

The canvas also carries sticky notes recording decisions and open
questions — read them, they are part of the spec.

If the canvas is unreachable, the same artboards are plain HTML in
`../design/*.dc.html`, and the design system is written out in
`../docs/DESIGN-SPEC.md`.

## Four decisions are deliberately unanswered

Listed in `../TASKS.md` §F0 and in the backend task list §B0. The most
important is the order-status vocabulary: the database has three
statuses, the designs use four. **Ask the repository owner. Do not
choose unilaterally** — every one of these changes shipped behaviour.

## Verification

Both repos treat `tsc` / `lint` / `flutter analyze` as necessary but
**not sufficient**. The established convention is verification against a
real database and a real browser or device. Report what you actually
ran, and say plainly what you could not verify.
