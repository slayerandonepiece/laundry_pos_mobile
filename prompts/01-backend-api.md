# Prompt — Phase 1: build the mobile API

Copy everything below into a fresh session, working in the `laundry_pos`
repository.

---

You are working in `laundry_pos`, a Next.js 16 + Prisma 7 + Postgres
(Neon) multi-tenant laundry POS. Your job is to build the HTTP API that a
Flutter mobile app will consume. **Do not start the Flutter app** — that
is a separate phase.

## Read first, in this order

1. `AGENTS.md` and `.agents/README.md` — scope and conventions.
2. `.agents/CURRENT-STATE.md` — what is actually built. Long, but it is
   the source of truth; skim all of it.
3. `.agents/MOBILE-API-TASKS.md` — **your task list.** Work through it in
   order.
4. `.agents/BACKEND-PLAN.md` §5 — the hardening items still open.

This repo pins an unusual Next.js version. Before writing routing or
server code, read the bundled docs in `node_modules/next/dist/docs/` —
APIs may differ from what you remember.

## The situation

There is **no API today.** Verified: `src/app/api` does not exist; the
only route handlers are three PDF renderers; `Authorization` and
`Bearer` appear nowhere in `src/`; there is no `middleware.ts`. Every
read is a Server Component and every write a Server Action, which is the
RSC wire protocol — an internal encoding keyed by a build id. A mobile
client cannot call it.

The good news: `src/server/services/*.ts` is already framework-agnostic,
zod-validated domain logic, and every function already takes `storeId`
first. `requireStoreSession(storeId, role)` already enforces role,
membership-active, store-locked, archived and payment-lapsed, computed
live per request.

## Non-negotiables

1. **This phase is additive.** The web workspace must keep working
   exactly as it does now. Do not break cookie auth while adding token
   auth.
2. **Do not duplicate domain logic into route handlers.** Handlers
   resolve auth, parse input, call a service, format the response.
   Business rules stay in `src/server/services/`.
3. **Authorization is never taken from the client.** `storeId` arrives as
   a request parameter, but `requireStoreSession` must still re-verify
   membership from the database on every call. Never read the
   `el_selected_store` cookie on an API route.
4. **Never trust client-submitted prices.** Order totals are recomputed
   server-side from the live catalogue (`src/server/pricing.ts`). Keep
   the `SELECT ... FOR UPDATE` lock in payment recording.
5. **Do not read or print `.env.local` values** — names only, never
   values, in code, logs, or your report.
6. **Dev database only.** Production's migration history was squashed and
   is not reconciled; read the "Critical caveat" in `CURRENT-STATE.md`
   before going anywhere near it.
7. **Stop and ask on the §B0 decisions.** Two of them change shipped
   behaviour — the order-status enum and whether employees may collect
   payments. Do the unblocked work first and ask at the right moment;
   do not guess and do not stall everything waiting.

## Definition of done

- `npx tsc --noEmit`, `npm run lint`, `npm run build` all clean. The
  `require()` warnings in `.cursor/hooks/graft-hooks.cjs` are
  pre-existing and unrelated — leave them.
- Integration tests per §B6, following the existing real-PostgreSQL
  pattern (`npm run test:subscription-payments`, `tests/README.md`), not
  mocks.
- The web workspace verified still working **in a browser** — a real
  login and a real order — not just a type-check.
- `.agents/CURRENT-STATE.md` updated: what you built, what was decided,
  what is still open.

## Report back

State what you built, what you ran, what passed, and — explicitly —
what you could **not** verify and why. If tests fail, say so and include
the output. Do not describe work as complete if any part was skipped.
