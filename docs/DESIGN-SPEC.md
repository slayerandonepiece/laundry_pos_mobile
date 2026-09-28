# KlenPOS mobile — design specification

The approved designs live in a Claude Design canvas (link in
`../prompts/README.md`; shared with anyone who has the link). This file
restates the design system in text so it can be implemented without
reading pixels off the canvas. **Where the two disagree, the canvas
wins** — but tell the repo owner rather than guessing.

Source of truth for the artboards: `../design/*.dc.html` (one file per
screen, plain HTML with inline styles) and `../design/canvas.json`
(layout). `_head.part` holds the v1 design system; `_head2.part` holds v2.

---

## 1. Two sets exist

- **v1 — approved, 48 screens.** Pure white surfaces. This is what
  to build unless told otherwise.
- **v2 — exploration, 9 screens.** A proposed redesign sitting to
  the right on the canvas. **Do not implement v2 without explicit
  sign-off.** Its differences are listed in §7.

## 2. Design tokens (v1)

Ported from the existing Next.js workspace so web and mobile read as one
product. Every value below is literal — do not round or substitute
Material defaults.

| Token | Value | Use |
| --- | --- | --- |
| Primary | `#0758d6` | buttons, links, selected states |
| Primary pressed | `#064bbb` | |
| Primary tint | `#eaf1ff` | icon tiles, selected chip fill |
| Selected surface | `#f5f9ff` | selected rows/cards |
| Page / card | `#ffffff` | |
| Inset surface | `#f7f9fc` | hints, grouped blocks — the only non-white fill |
| Text | `#102039` | |
| Muted text | `#5c6878` | secondary text (AA on white **and** on inset) |
| Faint text | `#667388` | tertiary, placeholders |
| Border | `#e8ecf1` | cards, dividers |
| Control border | `#dce2e9` | inputs, secondary buttons |
| Success | `#0f6e4c` on `#e7f5ef` | Paid, delivered |
| Warning | `#92400e` on `#fef3c7` / `#fffdf5` | Ready, unpaid, renewal due |
| Danger | `#b42318` on `#fef2f1` | balance due, overdue, destructive |
| Neutral pill | `#5c6878` on `#eff3f8` | Pending |
| Disabled | `#5a6578` on `#dbe2ec` | |

**Every pair above was verified ≥4.5:1 (WCAG AA).** If you change a
colour, re-check the contrast — several obvious-looking greys fail.

## 3. Type

- Display / numbers: **Manrope** 800, `letter-spacing: -0.04em`,
  tabular figures for all money.
- Body: **DM Sans**.
- Sizes in use: 29/26/24/22/20/19/18/17/15/14.5/14/13.5/13/12.5/12/11.5/11.
  **11px is the floor** for UI text (8.5px appears only inside the
  scaled invoice-paper preview, which is a document, not UI).
- Money is always INR `₹` in the UI. **In generated PDFs use `Rs.`** —
  Helvetica has no rupee glyph and renders `₹25` as `¹25`. This bug was
  already found and fixed once on the web side; do not reintroduce it.

## 4. Metrics

| | |
| --- | --- |
| Artboard | 390 × 844 (iPhone) |
| Status-bar inset | 59px, nothing painted in it — the OS draws over it |
| App bar | 56px content row, 18px below, 1px bottom border |
| Body padding | 20px |
| Card radius | 14px · control radius 9px · tile radius 12px |
| Card shadow | `0 1px 2px rgba(16,32,57,.05)` |
| Primary button | 52px · inputs 50–54px · nav items 52px |
| **Minimum touch target** | **44px, no exceptions** — text-only actions get padded hit areas via negative margin |
| Bottom nav | 10px top padding, 26px bottom (home indicator) |

Do **not** draw a fake status bar or a fake keyboard.

## 5. Navigation

- **Employee: 2 tabs** — New Sale, Orders.
- **Owner: 4 tabs** — Dashboard, New Sale, Orders, More.
- Features an employee cannot reach are **absent, never disabled**.
- Order detail and every step of the sale flow are **full screens with
  no bottom nav** — back arrow only. This is deliberate: it stops
  someone wandering out of a half-finished order.
- Everything under More is a pushed full screen.
- Both blocking screens keep the nav so sign-out is always reachable.

## 6. Screen inventory — v1 (build this)

Artboard file names match `design/<name>.dc.html`.

| Artboard | Screen |
| --- | --- |
| `Splash` | 1 · Splash |
| `LoginEmpty` | 2a · Login — empty |
| `LoginValidation` | 2b · Login — field errors |
| `LoginInvalid` | 2c · Login — wrong password |
| `LoginLoading` | 2d · Login — signing in |
| `LoginNoStore` | 2e · Login — no store linked |
| `ResetPassword` | 3a · Set new password |
| `ResetPasswordError` | 3b · Set new password — mismatch |
| `AccessBlocked` | 4 · Access blocked |
| `BlockedVariants` | 4a · All four block reasons |
| `NewSaleBrowse` | 5a · New sale — services |
| `NewSaleAdding` | 5b · Adding — kg field & stepper |
| `EditItem` | 5c · Edit or remove an item |
| `ClearCart` | 5d · Clear the sale |
| `CustomerDetails` | 6 · Customer — full screen |
| `Checkout` | 7 · Checkout — full screen |
| `OrderPlaced` | 8 · Order placed |
| `Main` | 9 · Orders — To collect |
| `OrdersEmpty` | 9a · Orders — first use |
| `OrdersNoResults` | 9b · Orders — no match |
| `OrderDetail` | 9c · Order detail — full screen |
| `StatusDialogDue` | 9d · Update status |
| `CollectDialog` | 9e · Collect payment |
| `OrderDone` | 9f · Order detail — settled |
| `OrderActivity` | 9g · Order activity & history |
| `InvoiceActions` | 9h · Invoice actions |
| `InvoiceViewer` | 9i · Invoice |
| `RbacLegend` | Access matrix |
| `OwnerDash` | A1 · Dashboard |
| `DashboardReports` | A2 · Dashboard — reports |
| `DateRange` | A3 · Reporting period |
| `OwnerSwitcher` | A4 · Switch store |
| `OwnerWarning` | A5 · Renewal due |
| `OwnerBlocked` | A6 · Plan expired |
| `OwnerOrders` | A7 · Orders |
| `OwnerOrderDetail` | A8 · Order detail — full screen |
| `OwnerServices` | A9 · Services |
| `ServiceEditor` | A10 · Edit service |
| `OwnerExpenses` | A11 · Expenses |
| `AddExpense` | A12 · Add expense |
| `MarkPaid` | A13 · Mark expense paid |
| `OwnerMore` | A14 · More |
| `OwnerStaff` | A15 · Staff |
| `AddStaff` | A16 · Add staff |
| `PaymentMethods` | A17 · Payment methods |
| `StoreProfile` | A18 · Store profile |
| `OwnerProfile` | A19 · Your details |
| `ChangePassword` | A20 · Change password |

`RbacLegend` and `BlockedVariants` are **reference sheets, not screens** —
do not build them.

## 7. Screen inventory — v2 (do NOT build without sign-off)

| Artboard | Screen |
| --- | --- |
| `V_Today` | V1 · Today — the counter's home |
| `V_Orders` | V2 · Orders — grouped by urgency |
| `V_OrderDetail` | V3 · Order detail |
| `V_CollectDialog` | V4 · Collect payment |
| `V_Dashboard` | V5 · Dashboard — one stat cluster |
| `V_NewSale` | V6 · New sale — typed tiles |
| `V_Checkout` | V7 · Checkout |
| `V_Expenses` | V8 · Expenses — unpaid first |
| `V_More` | V9 · More |

v2 differences: page ground becomes `#f7f9fc` with pure-white cards;
every row leads with a tinted service-type tile (wash `#eaf1ff`/`#0758d6`,
dry clean `#f0ebfd`/`#6d4bc7`, iron `#fef3c7`/`#92400e`); lists group by
urgency (Overdue / Due today / Upcoming) instead of relying on filters;
four dashboard figures collapse into one card; and `V_Today` is a new
screen with no v1 equivalent.
