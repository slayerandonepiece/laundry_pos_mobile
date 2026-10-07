# KlenPOS mobile — task list (Phase 2)

Flutter app for the Laundry POS backend. Branded **KlenPOS** (rebranded
2026-09-28, commit `feb909f`) — bundle ID / applicationId is
`com.reddygona.klenpos` (`.dev`/`.staging` suffixes per flavor). The Dart
package name (`myshop` in `pubspec.yaml`) is intentionally unchanged — an
internal identifier, not user-facing; see `docs/HANDOFF.md` "KlenPOS
rebrand + Firebase + gating" for the full rebrand scope.

## Current status — 1 October 2026

Release **1.0.4+6** is prepared for **stage** (branch `feat/dashboard-filters-and-sync-hardening`): `flutter analyze` clean, 800 tests pass. Done since 27 September: per-card dashboard period filters (7 days / current month / previous month / custom), drill-down tiles and Recent orders, Orders Work/Payment filters and employee quick filters, staff outlet assignment, sync/auth hardening (resume guard, backfill, dead-letter banner, cursor resume), backend outlet/invoice access fixes. The open task list is the **Pending list** in `docs/HANDOFF.md` (expense edit/delete, on-device verification passes, backend hardening leftovers, store listing). Release notes: `docs/RELEASE-NOTES-1.0.4.md`.

**2 October:** expense edit/delete/paid-date/outlet, backend hardening 2 and the parity-audit Batch A (mobile-only) are done and committed on the feature branches; statuses are in the Pending list and the 2 October note in `docs/HANDOFF.md`. Open: Batch B (needs backend endpoints), the Neon migration (user applies it), two device checks listed in the note. API error reporting was widened to report every failed call (4xx, 5xx, timeouts) to Crashlytics as non-fatals; see the 2 October note in `docs/HANDOFF.md`. It is uncommitted and not yet checked in a real Crashlytics project.

**7 October:** web-parity pass on `feat/web-parity-oct` (committed, not pushed): no-delivery-without-payment flow, catalog payment stages, Sync data page with stored message templates. Open items and the not-done list are in the 7 October note at the top of `docs/HANDOFF.md`. Next: Customer messages screen, then parity items 1, 2, 5, 6, 7.

## Status — 27 September 2026

The mobile HTTP API exists. Main `cdfc121` includes the merged offline-ID/outlet/local-first work. Historical F1–F8 details below are not a current test-count or exact navigation specification: owner navigation currently has Dashboard / Orders / More, employees use Orders without an owner bottom bar.

Current workspace fixes and verification: `docs/HANDOFF.md`. Manual device status: `docs/E2E-MANUAL-TEST.md`; remaining scripts: `docs/MANUAL-TEST-CASES.md`. New web enhancement backlog: `docs/WEB-MOBILE-FEATURE-GAPS.md` (60 open checks as of 1 Oct; offline behavior must be preserved).

Checkout now uses enabled store payment methods, including configured COD; do not use the older hardcoded Cash/UPI/pay-later description as a requirement. Full web parity remains pending.

Design system and screen inventory: `docs/DESIGN-SPEC.md`.
Working artboards: `design/*.dc.html`.

---

## F0 — Decisions inherited from Phase 1

Resolved 2026-09-26 — each answer keeps what the app already does.

| # | Decision | Answer |
| --- | --- | --- |
| F0.1 | `WorkStatus` — three values or four (does `Ready` / `Delivered` exist)? | **Four, as built**: Pending / In progress / Ready / Delivered |
| F0.2 | May an employee collect a balance? | **Yes** — Collect payment is not role-gated |
| F0.3 | Build v1 (white) or v2 (tinted + typed tiles)? | **v1, as built** — pure white surfaces |
| F0.4 | Is Flutter **web** a target? Decides whether the API needs CORS | **No** — strictly Android/iOS; the API needs no CORS for this app |

## F1 — Project setup

- [x] Fonts: Manrope (display) + DM Sans (body), bundled not fetched.
- [x] Theme from `docs/DESIGN-SPEC.md` §2–§4 as a single source of
  truth — colours, radii, the 44px touch floor, the 11px type floor.
  Build it once, do not hardcode colours in widgets.
- [x] INR formatting and **IST** date handling. The backend stores order,
  payment and expense *dates* as calendar dates with no time component,
  already resolved to the Asia/Kolkata day. Do not apply a second
  timezone conversion — that is how off-by-one-day bugs appear.
- [x] Linting and a CI-runnable `flutter analyze`.

## F2 — Shared widgets

Build these before screens; nearly every screen is made of them.

- [x] `AppScaffold` — 59px status inset, 56px app bar, 18px below.
- [x] `BottomNav` — 2-tab (employee) and 4-tab (owner) variants.
- [x] `AppCard`, `StatusPill`, `FilterChip` (44px), `MoneyText` (tabular),
  `PrimaryButton` / `SecondaryButton` (52px), `AppTextField` (50–54px).
- [x] `CentredDialog` — scrim + 16px radius + Cancel/confirm pair.
- [x] `TappableText` — text-only actions **with a 44px hit area**. The
  design uses negative margin so layout is unaffected.
- [x] `SectionHeader`, `EmptyState`, `BlockedScreen`.

## F3 — Auth and session

- [x] Splash, and all five login states: empty (action disabled), field
  validation, rejected credentials, in-flight, and
  authenticated-but-no-active-store.
- [x] Secure token storage (Keychain / Keystore — **not** SharedPreferences).
- [x] Forced password reset when the session reports
  `mustChangePassword`, including the mismatch state.
- [x] Blocked screen with all four reasons. The owner sees the exact
  paid-through date on a payment lapse; **staff never see figures or
  dates** — they get "check with your store owner" and a Call button.
- [x] Any request returning 401 → sign out and return to login. Access
  can be revoked mid-shift; the app must handle it on the next request,
  not crash.

## F4 — Role routing

- [x] Employee → 2 tabs. Owner → 4 tabs.
- [x] Owner-only screens must be **unreachable**, not disabled.
- [x] The client is **never** the authority. The API re-checks every
  request; treat a 403 as correct and render the blocked state.
- [x] Store switcher shown only when the caller has 2+ active
  memberships.

## F5 — Taking a sale (screens 5a–8)

- [x] Service list with search and category filters.
- [x] **Add control differs by unit**: a kg field for weighed services, a
  − / + stepper for per-piece. Added rows turn blue and show their
  computed amount with an Edit affordance.
- [x] Edit-or-remove dialog (5c) and Clear-sale confirm (5d).
- [x] Customer step: **phone required, name optional** — this matches
  `OrderCart.tsx` in the web app, where the name placeholder is
  literally "Optional".
- [x] Checkout: Cash / UPI / Pay on delivery. **Full amount or nothing —
  there is no partial payment anywhere in this app**, even though the
  backend supports it.
- [x] Send a client-generated **idempotency key** with order creation and
  reuse it on retry. `Order.idempotencyKey` already exists server-side;
  a double-tap must not create two orders.
- [x] Order placed (8) shows **no invoice actions** — the order is not
  settled yet.

## F6 — Orders and the collect-and-deliver loop (9–9i)

- [x] List: search (order, customer **or phone**), status filters, a
  "To collect" filter, empty state, and no-match state.
- [x] Order detail as a **full screen**, no bottom nav.
- [x] Update-status dialog: Pending / In progress / Ready. **Delivered is
  never set by hand.**
- [x] Collect-payment dialog: Cash or UPI for the whole amount; this one
  action records payment, marks the order delivered, and creates the
  invoice. Cancel · Done.
- [x] Activity & history screen: care instructions, delivery commitment
  (overdue / due today / upcoming), full status timeline with actor.
- [x] Invoice actions — inline **View / WhatsApp / More**, with More
  opening the full sheet (View, WhatsApp, Share, Download, Print).
- [x] Invoice actions appear **only once the invoice exists**. Before
  that, show the locked explanation.
- [x] **Prepaid delivery gap solved (Option B)**: an order paid at checkout
  is marked Delivered with customer invoice creation via a dedicated
  "Hand over order" confirm dialog when in Ready state.

## F7 — Owner screens (A1–A20)

- [x] Dashboard, reports (sales by service, money in/out, orders to
  finish), reporting-period picker.
- [x] Orders and order detail — **the same widgets as the employee's**,
  plus staff attribution. Do not fork these.
- [x] Services + editor, expenses + add + mark-paid, staff + add,
  payment methods, store profile, your details, change password.
- [x] **Store profile and Your details are separate screens** — store
  name/address/phone is the invoice header a customer sees; the owner's
  own name/username/email/phone is not. The web app mixes them on one
  page; mobile deliberately does not.

## F8 — Verification

- [x] Widget tests for the shared components in F2.
- [x] Role navigation tests (Employee 2 tabs vs Owner 4 tabs).
- [x] Login 5-state test suite.
- [x] Unit tests for CartBloc and sale flow (idempotency, piece/weight pricing).
- [x] Unit tests for OrdersBloc and filter logic.
- [x] Status dialog tests (Screen 9d: Cancel/Update buttons, Delivered locked notice).
- [x] Auth loop prevention tests (suppress 401 callback on login endpoints).
- [x] All 44 automated tests passing (including offline cache, sync status banner, forgot password dialog, collect payment loaders, and status dialog).
- [x] Offline-first architecture with Hive local cache, SyncStatusBar progress indicator, and queued sync action replay.

