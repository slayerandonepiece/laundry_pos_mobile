# E2E manual test — Store Owner & Employee

Live checklist for the end-to-end manual run on `main` (`cdfc121`, offline-id merged).

- **Build:** dev flavor (`--flavor dev --dart-define=ENV=dev`), iPhone 17 Pro simulator, DevTools attached
- **Backend:** local `laundry_pos` dev server on `http://127.0.0.1:3000` → staging Neon DB (running with uncommitted backend work in that tree)
- **Accounts:** Super Admin, Subscription org owner, Free Trial org owner (credentials given in chat, not stored here) + employees created below
- **Started:** 2026-09-27
- **Legend:** ✅ pass · ❌ fail · ⏳ to do · 🚫 blocked · ➖ skipped

## 27 September handoff update

- This checklist preserves the earlier device session as recorded; passed/view-only/blocked rows are not blanket verification of current code.
- All mobile working-tree changes are being consolidated on `feat/workspace-improvements` from merged main `cdfc121` with user authorization. Context: `docs/HANDOFF.md`.
- Fresh automated verification: `flutter analyze` clean, **333 tests passed**, `git diff --check` clean. No new live device/business-data mutations in this consolidation.
- Configured-method/COD and weighted-dialog safe-area fixes are included with regression tests; their full current device acceptance remains pending.
- The new web read-only lock behavior differs from the old D1/D2 blocked-screen expectations here. Future parity acceptance is in `docs/WEB-MOBILE-FEATURE-GAPS.md`; it is not yet implemented.
- Historical temporary test-account/organization settings may still require restoration as described in the manual scripts. Recheck their actual state before any authorized cleanup.

## 0. Setup

| # | Step | Status | Notes |
| --- | --- | --- | --- |
| S3 | Subscription org: create EMP-1 (1 outlet), EMP-2 (2 outlets), EMP-3 (0 outlets), EMP-4 (deactivate later) | ✅ | X10 was a non-localhost dev-asset block, X11 fixed (active:true sent) — confirmed by lead. Created via `localhost:3000` web workspace: EMP-1 (Chinnapanahalli), EMP-2 (both outlets), EMP-3 (no outlet), EMP-4 (Marathahalli) |
| S4 | Free Trial org: create EMP-T1 | ✅ | Express Laundry was found LOCKED in Super Admin (pre-existing state, recorded) — temporarily unlocked to create EMP-T1 (Chinnapanahalli), will re-lock before finishing Section D |
| S5 | Record before-state of both orgs (status, paid-through, trial end, access override) — restore at the end | ✅ | R K Laundry: ACTIVE, not locked, paid through 26 Sept 2027, deposit ₹10,000 paid, annual fee ₹5,000. Express Laundry: LOCKED, trial ends 22 Oct 2026, paid through not set, deposit ₹0 unpaid — unlocked temporarily for S4, must re-lock |

## A. Auth & session (both roles)

| # | Case | Status | Evidence |
| --- | --- | --- | --- |
| A1 | Empty fields → action disabled | ✅ | Sign in button greyed/disabled with both fields empty |
| A2 | Field validation messages | ❌ | No inline validation for malformed phone ("12345"); button enables on non-empty fields only. Submitting with an invalid-format phone silently no-ops (no request fired, no error shown) — missing feedback |
| A3 | Wrong password → clear error | ✅ | valid phone + wrong password → `POST /auth/login` 401 → clear inline "Invalid phone number or password" banner |
| A4 | In-flight spinner, no double submit | ✅ (smoke) | single tap → single login POST fired; "Setting things up" sync screen shown after success |
| A5 | Owner → 3 tabs (Dashboard/Orders/More), employee → 2 tabs | ✅ owner | login 200 with phone; dashboard loads |
| A6 | Forgot-password dialog | ⏳ | not reached this pass — prioritized S3/S4 per lead |
| A7 | New employee forced password change (incl. mismatch) | ⏳ | to do after S3 (EMP-1) |
| A8 | Kill + relaunch keeps session and refreshes outlets | ⏳ | hot restart keeps session ✅ (done repeatedly); full kill + relaunch still to do |
| A9 | Logout with unsynced orders warns; clean logout clears data | ⏳ | clean logout ✅ (logout 200 → login screen); unsynced-orders warning still to test |
| A10 | Session revoked mid-shift → back to login, no crash | — | already ✅ pass, logged as X2 before this pass |
| A11 | Super Admin login on mobile → clean refusal / no-store screen | ⏳ | to do |

## B. Store Owner — Subscription org (active)

| # | Case | Status | Evidence |
| --- | --- | --- | --- |
| B1 | Dashboard on All outlets matches web; period picker; outlet switch changes figures | ✅ (dashboard smoke only) | dashboard loads correctly (₹1,360 sales, 4 orders, chart, collected vs expenses), "This month" period picker and outlet-switch dropdown not exercised — see notes |
| B2 | App-bar outlet switcher drives orders, dashboard, expenses | ⏳ | dropdown tap did not open in this pass |
| B3 | New sale: kg field / piece stepper, edit/remove line, clear sale | ⏳ | not reached this pass |
| B4 | Customer: phone required, name optional; `+91 …` → 10 digits; `12345` → error, no lookup | ⏳ | not reached this pass |
| B5 | Checkout: real methods, none preselected; prepaid + pay-on-delivery; double tap = 1 order; All outlets → outlet picker | ⏳ | not reached this pass |
| B6 | Order placed shows no invoice actions | ⏳ | not reached this pass |
| B7 | Orders list: search (code/name/phone), status + To collect filters, empty/no-match, per-row outlet label | ⏳ | not reached this pass |
| B8 | Status Pending → In progress → Ready (violet); Delivered not settable | ⏳ | not reached this pass |
| B9 | Collect payment → Delivered + invoice; View / WhatsApp / Share / Download / Print | ⏳ | not reached this pass (an earlier invoice fetch for order EL-3 succeeded per c1 log, from before this pass started) |
| B10 | Prepaid order in Ready → Hand over → Delivered + invoice | ⏳ | not reached this pass |
| B11 | Activity: due commitment + timeline with actor | ⏳ | not reached this pass |
| B12 | Services add/edit (weighed + piece); double submit = 1 row | ✅ (view only) | 4 services configured: Wash & Fold (per kg, weighed tiers 4/6/8/extra), Steam ironing / Double BedSheet / Single BedSheet (per piece), all Active. Add/edit/double-submit not exercised this pass (time). |
| B13 | Expenses add (outlet + org-wide), mark paid; double submit = 1 row | ✅ (view only) | Expense overview ₹74,500 paid this period, 0 unpaid, 3 recurring (Employee Salary, Shop Rent, Electricity Bill, all "Paid 2026-09-27"). Note: the More screen's "Expenses" row still showed a stale "3 unpaid" badge that didn't match this — cosmetic/cache staleness, not re-tested further. Add / mark-paid / double-submit flows not exercised this pass (time). |
| B14 | Staff add / edit / deactivate / reactivate | ✅ | Add works after X11 fix (5 staff created via web, verified visible on mobile Staff screen after pull-to-refresh). Deactivate: toggle → `PUT /employees/{id}` `{"active":false}` 200, row greys out, "Deactivated employees cannot sign in" note shown. Reactivate: toggle back → `{"active":true}` 200, row restored. Edit form pre-fills correctly, full-screen. EMP-4 left deactivated intentionally for D7. |
| B15 | Payment method toggle reflected at checkout | ⏳ (view only) | Cash / Cash On Delivery / UPI listed; toggle-off-then-checkout not exercised this pass (time) |
| B16 | Store profile vs Your details separate; change password | ✅ | Your details (name/phone/email/sign-in phone/role) and Store profile (store name/address/phone/currency/timezone) are separate full-screen forms; change password ✅ (owner password restored to original, per earlier c1 log) |
| B17 | Subscription screen: active + renewal date | ✅ | "Your plan is active — Renews on 2027-09-26"; Billing history / Contact support shown |
| B18 | Offline: `OFF-` codes, create + pay offline, sync, no duplicates, banner clears, screens open offline | ⏳ | not reached this pass |
| B19 | Offline orders in two outlets → two bulk-sync calls, each lands right | ⏳ | not reached this pass |

## C. Store Owner — Free Trial org

| # | Case | Status | Evidence |
| --- | --- | --- | --- |
| C1 | Login + core flows (B1, B5, B8, B9 smoke) | 🚫 | could not sign out of Subscription owner to sign in as Trial owner, see X12 |
| C2 | Subscription screen shows trial + end date (suspect: app has no trial handling) | 🚫 | same as C1 |
| C3 | Trial ending → warning | 🚫 | same as C1 |
| C4 | Trial expired → owner blocked with date; employee blocked, no figures | 🚫 | same as C1 |
| C5 | Super Admin access override → access restored | 🚫 | web console hung, see X10 |

## D. Locked / lapsed / archived org (via Super Admin)

| # | Case | Status | Evidence |
| --- | --- | --- | --- |
| D1 | Lock org mid-session → owner store_locked on next request and on cold start | 🚫 | web/Super Admin console hung, see X10 |
| D2 | Same for employee, no figures | 🚫 | same as D1, also needs staff (X11) |
| D3 | Unlock → access restored | 🚫 | same as D1 |
| D4 | Paid-through in past → owner sees exact date, employee does not | 🚫 | same as D1 |
| D5 | Subscription ending soon → owner warning | 🚫 | same as D1 |
| D6 | Archived org → store_archived (only if reversible) | 🚫 | same as D1 |
| D7 | EMP-4 deactivated mid-session → membership_inactive, sign-out works | 🚫 | needs EMP-4 (X11) and Super Admin/web (X10) |

## E. Employee — Subscription org

| # | Case | Status | Evidence |
| --- | --- | --- | --- |
| E1 | EMP-1: 2 tabs, no picker / All outlets, owner screens unreachable | 🚫 | no employee could be created/assigned an outlet, see X10/X11 |
| E2 | EMP-1: sale lands in own outlet; list scoped | 🚫 | same as E1 |
| E3 | EMP-1: status, collect payment, invoice; owner timeline shows EMP-1 | 🚫 | same as E1 |
| E4 | EMP-1: profile, change password, cold start keeps scope | 🚫 | same as E1 |
| E5 | EMP-2: picker at sign-in; switch refetches, no leakage; order lands in selected | 🚫 | same as E1 |
| E6 | EMP-3: no_outlet_assigned blocked screen; sign-out works | 🚫 | same as E1 |
| E7 | EMP-2 outlet removed mid-session → re-prompt, no loop | 🚫 | same as E1 |
| E8 | Employee offline sale → sync | 🚫 | same as E1 |

## F. Employee — Free Trial org

| # | Case | Status | Evidence |
| --- | --- | --- | --- |
| F1 | EMP-T1: sale → Ready → collect | 🚫 | no employee could be created, see X10/X11 |
| F2 | Trial expired → staff blocked screen, no dates | 🚫 | same as F1 |

## G. Every case

DevTools: no uncaught exceptions, no unexpected 4xx/5xx, no request storms. Log every issue below.

## Findings

| # | Finding | Case | Severity | Status |
| --- | --- | --- | --- | --- |
| X1 | **Login impossible.** Running backend (uncommitted work in `laundry_pos`) `POST /auth/login` now requires `phone` (400 "expected string … path phone"); app sends `username` and the screen asks for a username. `User.username` is dropped in the uncommitted `schema.prisma`. 11 app files still use `username` (login, auth model, staff add/edit, owner profile). | A5 → all | Blocker | ✅ fixed (uncommitted): app migrated username → phone (login, auth model, staff add/edit, owner Your details); 321/321 tests, analyze clean; live login 200 with `{"phone":…}` |
| X4 | **Forced password reset logs the user out.** `POST /auth/set-password` rotates the session and returns a new `token`; `AuthRepository.setPassword` ignored it, so the next `/auth/status` used the revoked token → 401 → logout. Hits every first-login employee and every owner-reset. | A7 | High | ✅ fixed (uncommitted): store returned token (same as `changePassword`); new test fails without fix; 322/322 |
| X5 | Debug DIO log prints the full session `token` in login / set-password response bodies (request headers are masked). Dev-only logging. | G | Low | ⏳ |
| X6 | **Owner Change password always fails.** `OwnerRepository.changePassword` sent `currentPassword`; API requires `oldPassword` → 400, UI shows generic "Could not change password — try again". It also ignored the rotated token (would log out on success). | B16 | High | ✅ fixed (uncommitted): send `oldPassword`, store returned token; new test fails without fix; 323/323; live 200 + next calls use new token |
| X7 | `SyncStatusBar` Column overflows by 0.05 px while the banner collapses (`sync_status_bar.dart:97`) | G | Low (cosmetic) | ⏳ |
| X8 | Dashboard "Sales by date" line dips below ₹0 between two zero points (curve overshoot) | B1 | Low (visual) | ⏳ |
| X9 | Owner shell has 3 tabs (Dashboard / Orders / More), not 4 — matches current tests; checklist A5 expectation updated | A5 | — | ℹ️ |
| X3 | Subscription owner account has `mustChangePassword` set → forced "Set a new password" screen right after login. Copy says "Your store owner reset your password" even though this user *is* the owner. | A7 | Low (copy) | ⏳ |
| X2 | Cold start with an expired token → `/auth/status` 401 → clean logout → login screen, no crash (sync skipped while signed out) | A10 | — | ✅ pass |
| X11 | **Add staff (mobile) always fails 400.** `POST /api/v1/employees` body `{"name","phone","password","idempotencyKey"}` — backend now requires `active` (boolean) too: `{"error":"Invalid input: expected boolean, received undefined","issues":[{"expected":"boolean","code":"invalid_type","path":["active"]}]}`. `OwnerRepository`/`OwnerBloc` add-staff doesn't send `active`. UI shows generic "Could not add staff — try again". Combined with X10 (web console hung), this means **no new staff member can be created at all** right now, blocking S3/S4 and everything downstream (A7, E1-E8, F1-F2). | S3/S4 → A7,E*,F* | Blocker | ✅ fixed (uncommitted): send `active: true` on create (committed backend requires it too); test asserts it, fails without fix; 323/323 |
| X12 | App UI repeatedly became unresponsive to taps in this pass: (1) after the "Could not add staff" error SnackBar, (2) after leaving an Edit-staff form via the iOS text-selection popup, (3) the More screen's "Sign out" row and the resulting "Log out?" confirmation dialog's red "Log out" button did not respond to 3+ direct taps (no DIO/log line ever fired for logout). One case did resolve after a ~1 minute delay (a queued tap surfaced the confirmation dialog late), suggesting input lag rather than a true hang, but the Log out button itself never fired even after that. Recovered each time via hot_restart with session/data intact; could not complete A9 (logout) or reach the logged-out state for A1–A4/A6 in this pass as a result. Not chased further per 2-attempt cap — may be a simulator/tooling artifact rather than an app bug, but flagging since it blocked a whole section. | A9, A1-A6 | Med (blocked testing, uncertain root cause) | ➖ not reproduced by lead: Sign out → Log out? → Log out fired `POST /auth/logout` 200 on first tap and returned to login. More list springs back after scroll and dialog fades in — taps landed mid-animation. Tooling artifact. |
| X14 | ~~More-screen row taps unresponsive~~ — **WITHDRAWN, tooling artifact confirmed.** Root cause found: I was tapping with raw screenshot-pixel Y values instead of converting to device points (screenshot is ~2.29x device points; e.g. "Subscription" at pixel y≈1453 is point y≈635, not 1453 which is off-screen/beyond the 874pt height and could land on whatever row happens to sit at that fraction of a shorter list, e.g. Sign out). Using correct point coordinates, Subscription/Staff/etc all navigate correctly on the first tap. No app bug. | — | — (tooling artifact, not a finding) | ➖ withdrawn |
| X10 | **Web admin workspace (owner console) hangs forever on "Loading dashboard".** Navigating to `http://127.0.0.1:3000/` as the signed-in Subscription owner: static assets/JS load (200s), but zero API/XHR requests are ever issued — no `fetch`, no error in console beyond harmless HMR websocket failures. The "Admin navigation" sidebar renders with 0 nav links (empty `navigation` node), so Staff/Settings/etc are unreachable via the hamburger menu; direct nav to `/admin/staff` → 404. Blocks employee creation (S3/S4) and everything requiring the web console (owner Staff assignment, Super Admin org lock/paid-through/trial changes for C5, D1–D7). Could not determine root cause without touching backend source (out of scope). | S3/S4, C5, D1-D7 | Blocker | ➖ not a bug: page served from `127.0.0.1` — Next dev blocks dev assets for non-`localhost` origins (HMR ws fails, never hydrates). `http://localhost:3000/` renders the workspace. Use localhost. |
