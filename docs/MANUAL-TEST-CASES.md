# Manual test cases — mobile app (Owner & Employee)

Remaining cases from `docs/E2E-MANUAL-TEST.md`, written as step-by-step scripts. Mark each ✅ / ❌ and note anything odd. These are also the source for the future integration tests.

## Setup

- **App:** `main` + uncommitted fixes (phone login, set/change-password token, staff `active`). Dev flavor on the simulator or a device.
- **Backend:** `laundry_pos` dev server. Open the web console at `http://localhost:3000`, not `127.0.0.1`, or it never loads.
- **Orgs:**
  - **SUB**: R K Laundry. Active subscription, 2 outlets (Chinnapanahalli, Marathahalli).
  - **TRIAL**: Express Laundry. 1 outlet (Chinnapanahalli). ⚠️ It is currently **UNLOCKED** for testing. Its original state was **LOCKED**, so re-lock it at the end (see R1).
- **Staff already created.** Temporary password is in the scratchpad `test-accounts.md`. The first login forces a password change.

| Name | Phone | Org | Outlets |
| --- | --- | --- | --- |
| EMP-1 | 9000050001 | SUB | Chinnapanahalli |
| EMP-2 | 9000050002 | SUB | Chinnapanahalli (default) + Marathahalli |
| EMP-3 | 9000050003 | SUB | none |
| EMP-4 | 9000050004 | SUB | Marathahalli (used for D7) |
| EMP-T1 | 9000050010 | TRIAL | Chinnapanahalli |

- **Every case:** no crash, no red error screen, and no unexpected 4xx/5xx or request loops in DevTools → Network.

---

## A. Login & session

| # | Steps | Expected |
| --- | --- | --- |
| A2 | Login: enter phone `12345` and any password, then tap Sign in | Inline "Enter a valid phone number" (or similar). **Known fail (X13):** nothing happens and no error is shown |
| A6 | Login → tap "Forgot password?" | Dialog tells the user to ask their store owner / support. Closing it returns to login |
| A7 | Log in as EMP-1 with the temp password | "Set a new password" screen appears |
| A7a | On that screen, enter two different passwords | Mismatch error. Nothing is submitted |
| A7b | Enter a matching new password (8+ chars) | Lands on the employee home. Does **not** bounce back to login (X4 fix). Log out and log in again with the new password → works |
| A8 | Logged in as owner, swipe the app away (kill it) and relaunch | Opens straight to Dashboard, no login. Outlet list is current (rename an outlet on web first → the new name shows) |
| A9 | Turn on airplane mode, create 1 sale, then More → Sign out | Warning: unsynced orders will be lost. Cancel keeps you signed in and keeps the order |
| A9b | Go back online, wait for sync, then sign out | No warning. Returns to login. Logging in again as a different user shows none of the previous user's data |
| A11 | Log in on mobile as Super Admin | Clean message (no store / not supported on mobile). No crash, no empty shell |

## B. Owner — SUB org

Log in as the SUB owner.

| # | Steps | Expected |
| --- | --- | --- |
| B1 | Dashboard: change the period (Today / This week / This month) | Figures and chart change and match the web dashboard for the same period |
| B2 | App bar outlet switcher → Chinnapanahalli, then Marathahalli, then All outlets | Dashboard, Orders list and Expenses follow the selection. All outlets = sum of both |
| B3 | New sale: add a weighed service (enter kg) and a piece service (stepper +/−). Edit a line, remove a line, then Clear sale | Totals update live. Removed line is gone. Clear empties the cart after a confirmation |
| B4a | Customer: leave the phone empty and try to continue | Phone required error. Name is optional |
| B4b | Enter phone `+91 98765 43210` | Normalised to 10 digits; existing customer is looked up and filled |
| B4c | Enter phone `12345` | Validation error, no lookup request |
| B5a | Checkout | Only the store's real payment methods are listed, none preselected. Can't place the order until one is chosen (or Pay on delivery) |
| B5b | Place one prepaid order and one pay-on-delivery order | Both are created with the correct payment state |
| B5c | Double-tap Place order quickly | Exactly **one** order is created (check the list and the Network tab) |
| B5d | With **All outlets** selected, start checkout | Asks which outlet the order belongs to. The order lands in that outlet |
| B6 | Order-placed screen | No invoice buttons (the invoice exists only after delivery) |
| B7a | Orders: search by order code, customer name and phone | Each search finds the order |
| B7b | Filter by status and by "To collect". Search for gibberish | Filters narrow correctly. Empty/no-match state is shown, not a blank screen |
| B7c | All outlets view | Each row shows its outlet name |
| B8 | Open an order: Pending → In progress → Ready | Each change saves. Ready shows the violet badge. "Delivered" is **not** directly selectable |
| B9a | Order that is unpaid and Ready → Collect payment | Becomes Delivered and an invoice is created |
| B9b | Invoice: View, WhatsApp, Share, Download, Print | Each opens the right sheet or app. PDF shows correct lines and totals |
| B10 | Order that is prepaid and Ready → Hand over | Delivered + invoice, no payment step |
| B11 | Order → Activity | Due date shown. Timeline lists each change with who did it |
| B12 | Services: add a weighed service with tiers and a piece service, edit one, double-tap Save | Saved correctly. Double-tap creates **one** row. New service appears in New sale |
| B13 | Expenses: add one for an outlet and one org-wide, mark one paid, double-tap Save | Both appear under the right scope. Paid state updates. Only one row per save. The More → Expenses badge matches the unpaid count |
| B15 | Payment methods: turn off UPI, then open checkout | UPI is not offered. Turn it back on → it's offered again |
| B18a | Airplane mode on. Create 2 orders, and collect payment on one | Order codes start with `OFF-`. Sync banner shows pending. Orders, Dashboard and Order detail screens all still open |
| B18b | Airplane mode off | Banner syncs and clears. Orders get real codes. **No duplicates** in the app or on web |
| B19 | Offline: create one order in Chinnapanahalli and one in Marathahalli, then go online | Two bulk-sync calls (one per outlet). Each order ends up in its own outlet on web |

## C. Owner — TRIAL org

Log in as the TRIAL owner. Change trial dates in Super Admin (`localhost:3000/super-admin`).

| # | Steps | Expected |
| --- | --- | --- |
| C1 | Smoke test: Dashboard, one sale, Pending→Ready, collect, invoice | All work as in B |
| C2 | More → Subscription | Shows "Free trial" + trial end date. **Suspect fail:** the app has no trial handling, so it may say active or show nothing |
| C3 | Super Admin: set trial end to 3 days from now. Relaunch the app | Owner sees a "trial ending on <date>" warning |
| C4a | Super Admin: set trial end to yesterday. Pull to refresh or relaunch | Owner gets the blocked screen with the date and a contact / renew path. No data screens |
| C4b | Log in as EMP-T1 (same state) | Staff blocked screen. **No dates or money figures** shown to staff |
| C5 | Super Admin: add an access override (or extend the trial) | Owner and EMP-T1 get access back after refresh or relaunch |

## D. Locked / lapsed / archived — use SUB org, restore afterwards

| # | Steps | Expected |
| --- | --- | --- |
| D1 | Owner logged in on mobile. Super Admin: **Lock** SUB. On mobile, do any action (refresh orders) | Blocked "store locked" screen on the next request. Kill and relaunch → still blocked. Sign out works |
| D2 | Same, logged in as EMP-1 | Staff blocked screen, no figures, sign out works |
| D3 | Super Admin: **Unlock**. Refresh or relaunch | Owner and EMP-1 have normal access again. Unsynced offline orders (if any) sync |
| D4 | Super Admin: set paid-through to a past date | Owner: payment lapsed with the exact date. EMP-1: blocked **without** the date. Restore to **26 Sept 2027** |
| D5 | Super Admin: set paid-through to about 5 days from now | Owner sees a "subscription ending on <date>" warning. Employee sees none. Restore to 26 Sept 2027 |
| D6 | Skip unless archive can be undone. Archive → then unarchive | "Store archived" blocked screen. Access comes back after unarchive |
| D7 | EMP-4 logged in on mobile. Owner deactivates EMP-4 (web or mobile Staff) | On the next request EMP-4 sees "your access was removed" (membership_inactive). Sign out works. Reactivate EMP-4 → can log in again |

## E. Employee — SUB org

| # | Steps | Expected |
| --- | --- | --- |
| E1 | Log in as EMP-1 | 2 tabs only. No outlet picker, no "All outlets". Dashboard / Staff / Services / Expenses / Subscription are not reachable |
| E2 | EMP-1: new sale | Order lands in Chinnapanahalli (check on web). The order list only shows Chinnapanahalli orders |
| E3 | EMP-1: move the order to Ready → collect → open the invoice | Works. The owner's order timeline shows EMP-1 as the actor |
| E4 | EMP-1: Profile → change password. Then kill and relaunch | Password change succeeds and you **stay signed in**. After relaunch, still scoped to Chinnapanahalli |
| E5a | Log in as EMP-2 | Asked to pick an outlet at sign-in |
| E5b | Switch outlet | Lists refresh. No orders from the other outlet show. A new order lands in the selected outlet |
| E6 | Log in as EMP-3 | "No outlet assigned" blocked screen. Sign out works |
| E7 | EMP-2 logged in on Marathahalli. Owner removes Marathahalli from EMP-2. Refresh on EMP-2 | Moves to Chinnapanahalli automatically (only one left) or asks again. **No loop, no crash.** Restore EMP-2's outlets afterwards |
| E8 | EMP-1 offline: 1 sale, then go online | `OFF-` code → syncs to a real code, no duplicate, lands in Chinnapanahalli |

## F. Employee — TRIAL org

| # | Steps | Expected |
| --- | --- | --- |
| F1 | Log in as EMP-T1 (set the password first): sale → Ready → collect | Works, invoice created |
| F2 | Trial expired (see C4) | Staff blocked screen, no dates or amounts |

---

## R. Restore staging (do last)

| # | Step |
| --- | --- |
| R1 | Super Admin → Express Laundry → **Lock** again. Trial end back to **22 Oct 2026**. Paid-through not set. Deposit ₹0 |
| R2 | Super Admin → R K Laundry: ACTIVE, not locked, paid through **26 Sept 2027** |
| R3 | EMP-2 outlets back to both. EMP-4 active |

## Known open findings (from the first pass)

- **X13:** malformed phone on login does nothing, with no error (A2).
- **X3:** forced-reset message says "your store owner reset your password" even to an owner.
- **X5:** debug logs print the session token.
- **X7:** sync banner overflow of about 1px, seen on Dashboard and Staff.
- **X8:** sales chart line dips below ₹0.
- More → Expenses badge showed "3 unpaid" while the Expenses screen showed 0 (B13, not confirmed).
