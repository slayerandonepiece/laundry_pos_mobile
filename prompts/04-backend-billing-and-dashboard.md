# Prompt 04 — BACKEND (`../laundry_pos`) — never-billed orgs + dashboard granularity

Repo: /Users/reddygona/Documents/skills/laundry_pos (Next.js + Prisma). NOT the
Flutter repo. Read `CLAUDE.md`/`AGENTS.md` in that repo first and follow them.
Do not git commit. Do not touch the Flutter repo. Do not run anything against
production; use local/staging only, and if no such DB is configured, write the
script/test but do NOT execute it and say so.

Web behaviour must not regress: every change is either additive or scoped to the
mobile-API layer, unless a step says otherwise.

---

## BE1 — A created-but-never-billed organization must be blockable

Verified facts:
- `src/server/auth/session.ts` `getStoreAccessStatus()` (~:543-593) starts
  `subscriptionState = 'ACTIVE'` and only changes it when `trialEndsAt` or
  `paidThroughDate` exists. An org with NEITHER stays `ACTIVE` with
  `blockedReason` undefined, so login succeeds and nothing is restricted.
- `src/lib/subscriptionAccess.ts:5` `isSubscriptionLapsed` returns false when
  both dates are absent (`!!(paidThrough || trialEnds) && ...`).
- The super-admin lifecycle already models this state:
  `src/server/services/store-lifecycle.ts:49` returns `'TERMS_NOT_SET'` for
  exactly this case (see also `src/features/super-admin/lifecycle.ts`,
  `StoreOverviewTab.tsx:27`). The API layer just doesn't expose it.
- `src/server/api/membership-context.ts` (:32-64) builds `stores[]` /
  `organizations[]` for `/auth/login`, `/auth/status`, `/memberships` from
  `getStoreAccessStatus`.
- Contract text: `.agents/MOBILE-API-CONTRACT.md` ~:88-112.

Design decision to implement (state it in your report):
- Keep `subscriptionState` enum values as they are for the web; ADD a new
  additive `blockedReason` value `billing_pending` (add to `AccessDeniedReason`)
  and a new `subscriptionState` value is NOT added. For the mobile API layer
  only (`membership-context.ts`): when the org has neither `trialEndsAt` nor
  `paidThroughDate` AND no active `accessGrantedUntil` override AND is not
  LOCKED/archived, return `blockedReason: 'billing_pending'`,
  `subscriptionState: 'RESTRICTED'`, `isLocked` unchanged.
- Do NOT change `getStoreAccessStatus`'s behaviour for web sessions in this
  step. If the cleanest implementation requires changing it, STOP and report
  why instead — web login for orgs that a super admin is still setting up must
  not silently break.
- SAFETY CHECK BEFORE ENABLING: existing orgs may legitimately have no terms
  (legacy, or mid-setup by a super admin). Write a read-only script
  `scripts/count-terms-not-set.ts` that prints how many non-archived orgs have
  neither date, and their ids/names. Run it on local/staging only. Gate the new
  behaviour behind an env flag `MOBILE_BLOCK_TERMS_NOT_SET` (default `false`),
  so shipping the code blocks nobody until the owner flips the flag after
  reviewing the script's output.
- Also make sure the owner can still recover: a blocked org's OWNER must still
  be able to reach whatever billing/payment route exists on the web. Find it
  (grep billing/payment/subscription routes under `src/app`) and report the URL
  path the mobile app can open for "Complete payment". If none exists, say so.

Update `.agents/MOBILE-API-CONTRACT.md` (blockedReason list + this behaviour +
the env flag) and `API_ENDPOINTS.md` if it lists blockedReason values.

Tests: unit test `membership-context` for: never-billed + flag off → unchanged;
flag on → `billing_pending`/`RESTRICTED`; flag on + trial set → unchanged; flag
on + `accessGrantedUntil` in the future → unchanged; LOCKED still wins.

## BE2 — `/api/v1/dashboard`: granularity for the mobile 7/30/90-day charts

Verified facts (`src/app/api/v1/dashboard/route.ts`,
`src/features/admin/admin.analytics.ts` `dashboardData` / `intervals`):
- `bars = intervals(range, 12)` — up to 12 buckets over the REQUESTED range.
  For 30 days step = ceil(30/12) = 3 days (10 buckets); for 90 days step = 8
  days (12 buckets). Not weekly/monthly.
- `cash = intervals(rangeFor('month'), 5)` — ALWAYS the current calendar month,
  5 buckets, regardless of the `from`/`to`/`period` the client asked for.
- The route accepts `period`, `from`, `to`, `outletId`.

Task (additive, defaults unchanged so the web dashboard is untouched):
1. Verify and report exactly which keys `dashboardData` returns
   (`bars`, `cash`, …) and their shapes.
2. Add an optional query param `granularity=day|week|month` to the route. When
   present it changes only how `bars` is bucketed: `day` = one bucket per day;
   `week` = Monday-start weeks clipped to the range; `month` = calendar months
   clipped to the range. Labels: single day → existing `dateLabel`; multi-day →
   `"<from>–<to>"` using the same `dateLabel` format already used. Invalid
   value → 400 via the existing handler. Absent → current behaviour, byte for
   byte.
3. Add optional `series=cash` behaviour ONLY if trivial: make `cash` honour the
   requested `range` when `from`/`to` are given (today it ignores them). If that
   would change what the web dashboard shows, do NOT change it; instead add a
   new key `cashRange` (same shape as `cash`, bucketed with the requested
   granularity over the requested range) and leave `cash` as is.
4. Document both in `.agents/MOBILE-API-CONTRACT.md` and `API_ENDPOINTS.md`.
5. Tests for `intervals`/granularity: 7 days day-granularity = 7 buckets; 30
   days week-granularity = 5 buckets max, first/last clipped; 90 days month =
   3-4 calendar-month buckets; range ending in the future is clipped to today.

---

## Verification (real output)
- the repo's typecheck (`npx tsc --noEmit`), lint, and test commands from
  package.json → all pass
- `git diff --stat` → only the files named above + their tests + docs + the
  one script
- Final report: exact final JSON shape of the changed endpoints (before/after),
  the env flag name and default, the script's output (or "not run: no local DB"),
  and the billing URL path (or "none exists"). Say explicitly what you could not
  verify.
