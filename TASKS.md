# MyShop mobile — task list (Phase 2)

Flutter app for the Laundry POS backend. "MyShop" is a **working title**
— it appears only on the splash and login screens, never on anything a
customer sees. The Flutter package is `myshop` / `com.myshop`; renaming
is cheap now and expensive after the first store install.

> **Phase 1 must be finished first.** See
> `../laundry_pos/.agents/MOBILE-API-TASKS.md`. As of 2026-09-11 the
> backend has **no HTTP API at all** — no `src/app/api`, no
> `Authorization` header handling anywhere, no middleware. There is
> nothing for this app to call. Do not start F3 until the API is real.

Design system and screen inventory: `docs/DESIGN-SPEC.md`.
Working artboards: `design/*.dc.html`.

---

## F0 — Decisions inherited from Phase 1

These were left open deliberately. Confirm the answers before building
the affected screens; do not guess.

| # | Decision | Blocks |
| --- | --- | --- |
| F0.1 | `WorkStatus` — three values or four (does `Ready` / `Delivered` exist)? | order detail, status dialog, invoice trigger |
| F0.2 | May an employee collect a balance? | screen 9e |
| F0.3 | Build v1 (white) or v2 (tinted + typed tiles)? Default: **v1** | every screen |
| F0.4 | Is Flutter **web** a target? Decides whether the API needs CORS | — |

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

