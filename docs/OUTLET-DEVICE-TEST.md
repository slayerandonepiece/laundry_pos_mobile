# Outlet parity — device test log

Live checklist for the on-device verification of `docs/OUTLET-PARITY-SPEC.md` (O10)
and `../laundry_pos/.agents/MOBILE-API-CONTRACT.md`.

- **Build:** Dev flavor (`--flavor dev --dart-define=ENV=dev`), iPhone 17 Pro simulator
- **Backend:** local `laundry_pos` `npm run dev` on `http://127.0.0.1:3000` (same DB as staging)
- **Started:** 2026-09-26
- **Legend:** ✅ pass · ❌ fail · ⏳ to do · 🚫 blocked (needs something listed)

Test data created on the backend by this run (additive, not removable from the app):

| Order | Outlet | Amount | Payment | Notes |
| --- | --- | --- | --- | --- |
| EL-8 | Reddy's Laundry – HSR Layout | ₹20 | Pay on delivery (none recorded) | Walk-in, 9876543210 |

---

## A. Owner — Reddy's Laundry (outlets: Chinnapnahalli, HSR Layout, + All outlets)

| # | Case | Status | Evidence |
| --- | --- | --- | --- |
| A1 | Sign in; no 403 on any call | ✅ | login 200; profile/products/orders/dashboard/expenses all 200 |
| A2 | Lands on **All outlets**; `/dashboard` sent without `outletId` | ✅ | `GET /api/v1/dashboard` (no query) |
| A3 | Dashboard vocabulary: Open orders, Delivered, Collected, "Collected vs expenses — this month" | ✅ | screenshot |
| A4 | Switch outlet → `/dashboard?outletId=…`, figures change | ✅ | ₹3,064.55/7 → ₹544.55/3 (HSR) |
| A5 | Orders list follows scope; delta sync restarts per outlet | ✅ | HSR 3 orders = dashboard; `orders/sync?limit=50` (no `since`) after switch |
| A6 | New sale with a specific outlet → no picker; outlet shown at checkout | ✅ | "Reddy's Laundry – HSR Layout" above payment block |
| A7 | New sale in **All outlets** → outlet picker sheet first | ✅ | "Select outlet" sheet; picked Chinnapnahalli |
| A8 | Phone paste `+91 98765 43210` → `9876543210` on blur; lookup uses it | ✅ | `customer-lookup?phone=9876543210` |
| A9 | Phone `12345` → inline error, no lookup | ⏳ | `12345` typed in Chinnapnahalli new order; blur + check error/no `customer-lookup` still to do |
| A10 | Checkout shows real methods (COD, Card, Cash, Upi), nothing pre-selected, Place order disabled | ✅ | screenshot |
| A11 | Pay-on-delivery order lands in the chosen outlet only | ✅ | EL-8 in HSR; absent from Chinnapnahalli |
| A12 | Payment methods screen: toggles only, no Add/Rename, helper copy | ✅ | screenshot |
| A13 | Expense form hint — specific outlet | ✅ | "…recorded against Reddy's Laundry – Chinnapnahalli." |
| A14 | Expense form hint — All outlets ("organization-wide") | ✅ | screenshot |
| A14b | Orders list in All outlets shows per-row outlet label (O5.3) | ✅ | 8 orders, ₹3,084.55, each row labelled |
| A15 | `Ready` pill violet, distinct from amber payment pills | ⏳ | move EL-8 → Ready |
| A16 | Dashboard donut "Ready" slice violet | ⏳ | after A15 |
| A17 | Collect payment dialog: real methods, nothing pre-selected | ⏳ | on EL-8 (do not submit a payment) |
| A18 | Offline: orders in two outlets → two separate bulk-sync calls, each lands right | ⏳ | stop backend, place 2 orders, restart |

## B. Employee — one outlet

| # | Case | Status | Evidence |
| --- | --- | --- | --- |
| B1 | Sign in; orders list loads (the original 403 bug) | 🚫 | user to sign in |
| B2 | No outlet picker; no "All outlets" option | 🚫 | |
| B3 | Punch an order → lands in that outlet | 🚫 | |
| B4 | Cold start (kill + relaunch) keeps scope, refreshes outlets via `/auth/status` | 🚫 | |

## C. Employee — two outlets

| # | Case | Status | Evidence |
| --- | --- | --- | --- |
| C1 | Picker (OutletRequiredScreen) at sign-in | 🚫 | user to sign in |
| C2 | Switching empties + refetches; no row from the other outlet survives | 🚫 | |
| C3 | Order lands in the selected outlet | 🚫 | |

## D. Edge cases (need account/data setup)

| # | Case | Status | Needs |
| --- | --- | --- | --- |
| D1 | Employee with **zero** outlets → blocked screen, sign-out works | 🚫 | such an employee account |
| D2 | Outlet membership removed mid-session → re-prompt (not empty list, not sign-out loop) | 🚫 | web workspace access to edit membership |
| D3 | Org with **no enabled methods** (One Wash) → empty-state copy, prepaid disabled | 🚫 | One Wash owner sign-in |
| D4 | Rename/disable method in workspace → mobile checkout follows | 🚫 | web workspace access |

---

## Findings (bugs / oddities seen during the run)

| # | Finding | Severity | Status |
| --- | --- | --- | --- |
| F1 | Payment methods screen subtitle shows "Cash" under Card and COD — new API has no `type`; model guesses | Low (label) | ⏳ fix later |
| F2 | `GET /orders/sync` fired before sign-in → 401 | Low | ⏳ investigate |
| F3 | After sign-in, `/dashboard` loaded 3× and `/expenses` 2× | Low (perf) | ⏳ investigate |
| F4 | Delivered orders' invoices re-downloaded on every outlet switch | Low (perf) | ⏳ investigate |
| F5 | `POST /orders/bulk-sync` took 10 s server-side for 1 action | Watch | backend |
| F6 | Org has a method named "COD" ("Pay full amount now") next to "Pay on delivery" — confusing for staff | Product/data | ⏳ owner decision |
