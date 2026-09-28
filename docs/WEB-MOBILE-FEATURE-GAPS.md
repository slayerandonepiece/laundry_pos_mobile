# Web → Flutter enhancement audit and acceptance checks

Date: 27 September 2026

## Scope and evidence

Compared the current working source, including uncommitted changes, in `../laundry_pos` and `laundry_pos_mobile`. Store owner and employee features are in scope. Super Admin management screens are not automatically mobile requirements. No application code changed. This document is a source audit, not proof that the checks below pass on a device. All acceptance boxes are intentionally unchecked.

Mobile offline operation is a required existing capability. New features must extend its current repositories, caches and synchronization contracts. Replacing Flutter's data flow with the web's fetch behavior is outside scope.

Legend: **Gap** = missing enhancement confirmed in source; **Partial** = capability exists with a specific missing part; **Parity** = underlying capability exists in both, runtime checks still needed; **Decision** = different behavior that should not be changed automatically.

Paths below are repository-relative. Web paths start `../laundry_pos/`; other paths are Flutter paths.

## Feature inventory

| Area | Existing Flutter capability to preserve | Enhancement status |
|---|---|---|
| Dashboard | Today/period totals, custom dates, operational counts, collection/expense chart, order-status chart, service mix, single/all outlet scope, cached reads | Partial: booked-sales trend, previous-period comparison, per-outlet cards, recent orders and attention drill-down |
| Owner orders | Date ranges, due-today/late, search, status and paid/unpaid/part-paid filters, sales/collected/balance summary, outlet labels, new sale | Substantial parity; check semantics and legacy data |
| Employee orders | Search, work-status chips, To collect, new sale, status/payment actions | Partial: web register also provides date/delivery and separate payment-status filters |
| POS | Piece/weight services, slab pricing, customer lookup, delivery date, care notes, received payment, payment methods, owner outlet selection | Substantial parity; category vocabulary differs |
| Order details | Customer, charges, balance, payments, status changes, notes, history | Substantial parity; lock read-only behavior missing |
| Invoices | View, locally generated PDF, print, native file sharing, Ready bill flow, server invoice allocation/retry | Partial: public invoice-link delivery and server PDF presentation differ |
| Products/services | Search, categories, add/edit, active status, piece/weight/slab prices | Substantial parity; category vocabulary and legacy-unit guidance differ |
| Expenses | Search, period/unpaid/recurring filters, create, mark paid, recurrence metadata, cache and offline owner actions | Gap: details/edit/delete, chosen paid date, explicit outlet/organization assignment |
| Staff | Search, add/edit name and phone, activate/deactivate, cache and queued updates | Gap: outlet/default assignments, assignment display, temporary password reset |
| Outlets | Allowed outlets, default/single/all selection, scope isolation, access-loss handling | Gap: owner directory and outlet detail/report screens |
| Profile | Owner/store details forms, password change, employee profile, sign out | Partial: account/contact distinction, billing fields, outlet facts and security metadata |
| Payment methods | Platform-defined methods and organization enable/disable, checkout integration, queued toggles | Partial: disable confirmation |
| Subscription/access | Paid-through summary, blocked-state handling | Gap: trial display, pre-expiry notices and locked read-only workspace |
| Announcements | No matching Flutter flow found | Gap: delivery API, presentation, targeting, refresh, dismissal and links |
| Auth/session | Phone login, first password change, session revocation, outlet re-resolution | Substantial parity; preserve and test with new access state |

## Dashboard

**D1 — Gap: booked-sales trend and previous-period comparison.** Web `Dashboard.tsx:93` renders `d.bars` with `previousPoints`; `admin.analytics.ts:44` builds these from order creation dates and order totals. Flutter `owner_dashboard_screen.dart:835` plots `cash[i].income`, which represents collected payments; `dashboard_model.dart:43` does not retain `bars`. This is a metric gap, not merely a chart design difference. Web's cash series is month-based even when the booked-sales range changes.

- [ ] D1.1 An order booked today with payment tomorrow contributes to today's booked sales and tomorrow's collections, without conflating them.
- [ ] D1.2 Selected range and comparison series use the intended same-duration periods; default 14-day reporting is available if web parity is adopted.
- [ ] D1.3 Zero-sales periods stay zero. Flutter currently substitutes today's values when `periodSales`/`periodOrders` are zero (`owner_dashboard_screen.dart:484`); distinguish a valid zero from unavailable data.
- [ ] D1.4 Offline charts clearly show the cached scope/range. Preserve the existing default-period cache; a cached month must not appear to be a newly fetched custom range.

**D2 — Gap: per-outlet performance cards.** Web `Dashboard.tsx:98` shows outlet sales, orders, open orders, best-outlet share and yesterday comparison. Flutter supports All outlets, but lacks this breakdown/model consumption. The web also has `/api/v1/dashboard/rollups`; Flutter's endpoints currently expose only the main dashboard route.

- [ ] D2.1 All-outlet totals reconcile with per-outlet figures, with organization-wide records accounted for explicitly.
- [ ] D2.2 Empty/inactive outlets and zero yesterday sales render without misleading growth percentages.
- [ ] D2.3 Opening an outlet detail never silently changes a queued sale's original outlet.

**D3 — Gap: recent orders and filtered attention navigation.** Web `Dashboard.tsx:46` links attention to the filtered register and `:67` provides recent orders with direct details. Flutter `owner_dashboard_screen.dart:631` routes Open orders/Delivered/Due today through the same argument-free callback; the current shell callback only changes tabs. No recent-orders section is rendered in the dashboard composition at `:284`.

- [ ] D3.1 Due today, overdue and open-order actions open the intended result set, rather than the default register.
- [ ] D3.2 Recent orders are newest first, show the right outlet in aggregate scope, and open the selected order.
- [ ] D3.3 Offline drill-down uses cached orders and retains existing tab-reset behavior except for explicitly supplied filters.

## Orders, POS and invoices

**O1 — Partial: employee register filters.** Web `Sales.tsx` offers date selection, Due today/Late and a separate payment-status selector for its register. Flutter owner orders already have these; employee `OrdersState.filteredOrders` and `orders_list_screen.dart:283` expose search and a combined status/To collect chip set.

- [ ] O1.1 Employee can combine work status, payment status and delivery/date scope where required, without gaining owner financial summaries or broader outlet access.
- [ ] O1.2 Search, clear/reset, chip counts and empty results agree with the filtered cached dataset.

**O2 — Parity: core operations already exist.** Sources: `owner_orders_screen.dart:326`, `order_detail_screen.dart`, `order_activity_screen.dart:138`, `customer_details_screen.dart`, `checkout_screen.dart`, and `orders_repository.dart:157`. Do not rebuild these as new features.

- [ ] O2.1 Owner date filters and due/late shortcuts have the same semantics as web; due/late searches can include orders created outside the selected period.
- [ ] O2.2 Four statuses, partial/full payments, balance and history reconcile after refresh and replay.
- [ ] O2.3 Customer lookup handles existing/new customers and failures; cached lookup continues offline.
- [ ] O2.4 Piece/weight slab boundaries, additional kg rates, notes, delivery dates, advance/COD choices and inactive methods retain current behavior.

**O3 — Partial: public invoice links.** Web `OrderInvoicePdfViewer.tsx:16` uses tokenized `/i/<token>/view` links, server PDF preview, share/link fallback and download. Flutter `invoice_actions_sheet.dart:295` shares a generated PDF attachment and prints locally. Native file sharing is already implemented and should stay. A public-link/open-in-browser option is an additional enhancement, not a replacement for local PDF generation.

- [ ] O3.1 A synchronized final invoice can optionally share/open the server-issued public URL without embedding bearer credentials.
- [ ] O3.2 Existing local PDF view/print/file sharing continue when offline.
- [ ] O3.3 Unsynced/Ready bills remain clearly distinct from a final server-numbered invoice; retry does not allocate a duplicate invoice.
- [ ] O3.4 Server and local PDF agree on invoice identity, store/outlet/customer details, quantities, totals and payment state.

**O4 — Parity with a legacy compatibility check.** Server list reads exclude cancelled records (`orders.ts:137`), delta sync sends `deleted` tombstones (`:229`), and Flutter removes them (`orders_repository.dart:730`). Cancellation synchronization already exists. Flutter recognizes only `Delivered` as delivered; verify historical normalization with fixtures rather than treating this as a confirmed new feature gap.

- [ ] O4.1 Legacy cancelled/completed fixtures do not inflate open orders, balance, sales or deliverable work.
- [ ] O4.2 New four-status orders and cached offline orders retain their existing identity/merge behavior.

## Products/services

**P1 — Decision: category vocabulary.** Web `ProductEditorContainer.tsx:75` offers Laundry, Dry cleaning, Ironing, Home fabrics, Add-on. Flutter `services_screen.dart:826` offers wash, dry clean, iron, premium, laundry and preserves an edited product's existing category. Both store categories as strings. Do not rename existing records or caches as part of parity work.

- [ ] P1.1 Agree the choices for newly created services; existing categories stay searchable/editable.
- [ ] P1.2 A web-created Home fabrics/Add-on service appears and can be edited in Flutter without category loss.

**P2 — Partial: legacy-unit guidance.** Web `Catalogue.tsx` identifies inactive legacy products needing unit confirmation with a Confirm unit label. Flutter defaults missing `type` to item (`product_model.dart:46`) and has no equivalent guidance. Verify real legacy payloads before changing behavior.

- [ ] P2.1 Legacy entries cannot be sold with an assumed incorrect unit; existing active piece/weight products remain unchanged.
- [ ] P2.2 Add/edit, activation, pricing and category search retain current parity. Product editing is currently a direct API path; do not claim it already supports queued offline writes.

## Expenses

**E1 — Gap: details, edit and delete.** Web has `ExpenseDetails.tsx`, `DeleteExpenseDialog.tsx` and update/delete Server Actions. Flutter expense rows only invoke mark-paid for unpaid entries (`expenses_screen.dart:713`); `OwnerRepository` has create/mark-paid but no update/delete. Mobile API has collection GET/POST and pay POST, with no expense-detail update/delete routes.

- [ ] E1.1 View all bill facts, edit supported fields, and cancel edits without mutation.
- [ ] E1.2 Confirm deletion and reflect updated totals; cover paid and recurring bills so a deleted series is not recreated by a later read.
- [ ] E1.3 Add API/repository contracts before exposing controls. New queued edit/delete actions need explicit replay/conflict policy while preserving existing create/pay actions.

**E2 — Gap: chosen paid date.** Web `MarkExpensePaidDialog.tsx` submits a selected date. Flutter sends `{}` (`owner_repository.dart:307`), and API pay POST does not consume a date.

- [ ] E2.1 A past paid date is retained through online save, offline queue and replay; future dates are rejected.
- [ ] E2.2 Collection/expense charts count payment on the selected date, not reconnect time.

**E3 — Gap: explicit organization/outlet attribution.** Web `ExpenseEditor.tsx:29` offers Organization-wide or a selected outlet. Flutter's expense model drops `outletId`, and creation relies on current outlet scope/header rather than a form choice.

- [ ] E3.1 Select attribution explicitly; show it in lists/details and retain it through serialization.
- [ ] E3.2 Aggregate vs single-outlet filtering and dashboard totals agree; a queued expense stays attached to its original scope after switching outlets.

## Staff

**S1 — Gap: assignments/default outlet.** Web employee UI displays assigned/default outlets, warns about unassigned staff and edits assignments. Flutter `staff_model.dart` retains only id/name/phone/active; create/update payloads (`owner_repository.dart:424`, `:584`) omit outlets/defaultOutletId. The backend supports these fields. Creation with no outlets creates no outlet memberships, so a new mobile-created employee can lack operational outlet access.

- [ ] S1.1 Add/edit employee supports allowed outlets and a default that belongs to the selection.
- [ ] S1.2 Existing assignments survive ordinary name/phone edits and queued replay.
- [ ] S1.3 Assignment badges, no-outlet warning and assignment recovery match server truth.
- [ ] S1.4 Employee sees only granted outlets after refresh/relogin; removing the active outlet preserves current access-loss recovery.

**S2 — Gap: temporary password reset.** Web `ResetEmployeePasswordDialog.tsx` and service reset end current sessions and require password change. Flutter has no owner reset flow. Current PUT can update a password, but a dedicated reset contract or deliberate reuse must be confirmed for full semantics.

- [ ] S2.1 Owner-only reset validates confirmation and forces affected staff sessions out/first password change.
- [ ] S2.2 Reset requires connectivity; never persist raw temporary passwords in the offline owner-action queue.

## Outlets

**L1 — Gap: directory and detail.** Web `OutletsList.tsx:18` displays name/code/status/opened date/address and View. `OutletDetail.tsx` renders outlet snapshot, trend and order-status report with closed/relocated states. Flutter only has allowed-outlet selectors and its smaller outlet model; no corresponding owner screens or directory/detail endpoints were found.

- [ ] L1.1 Owner can view full outlet facts and correctly scoped analytics, including closed/relocated history where authorized.
- [ ] L1.2 Staff cannot inspect unrelated branches. Viewing detail does not change the active operational outlet implicitly.
- [ ] L1.3 Preserve platform provisioning: web owners also contact support to add/relocate outlets. Do not invent native owner provisioning.

## Profile, payment methods and authentication

**A1 — Partial: profile information.** Web `Profile.tsx:82` separates login phone from organization contact, displays billing plan/deposit/annual fee/paid-through, outlet facts, and security metadata. Flutter separates owner/store forms but the profile DTO contains only store/address/contact phone/email/name; subscription uses only paidThroughDate. API `/profile` does not supply web's added billing/outlet/security fields.

- [ ] A1.1 Label editable phone as organization contact; show immutable login phone separately.
- [ ] A1.2 Owner can inspect plan/deposit/fee and outlet facts; employees do not receive/display owner-only billing details.
- [ ] A1.3 If adding Password last changed, use an actual password-change timestamp. Web currently derives its label from general user `updatedAt`, so copying that uncritically would be misleading.

**A2 — Partial: payment-method disable confirmation.** Web `PaymentMethodsSettings.tsx` explains organization-wide impact and confirms disabling. Flutter switch immediately dispatches a queued-capable toggle (`payment_methods_screen.dart:183`).

- [ ] A2.1 Confirm disable, cancel leaves state intact, and explain impact across outlets.
- [ ] A2.2 Preserve queued toggles and method codes/COD behavior; historical payments still display after a method is disabled.

**A3 — Parity: auth and password changes.** Phone login, must-change-password, expiry/revocation and logout already exist in Flutter. No new auth architecture is required for this audit.

- [ ] A3.1 Wrong password, inactive membership, archive, expired token and outlet revocation retain distinct outcomes.
- [ ] A3.2 Password change revokes the old token and saves the API-issued replacement token before subsequent calls; intentional logout still applies its existing cache policy and no queued records leak into another account.

## Trial, lock and announcement notices

**N1 — Gap: trial/status notices.** API membership context returns trialEndsAt/subscriptionState in organizations, but Flutter store parsing drops them. Web `AdminChrome.tsx:107` shows a non-dismissible trial strip; warning threshold is 7 days; paid warning is 30 days, whereas Flutter subscription screen uses 7 days and has no shared paid-warning strip.

- [ ] N1.1 Active trial/end date, trial ending, paid active/ending and expired states are server-derived and correctly scoped.
- [ ] N1.2 Owner action opens appropriate details; employee notices retain intended privacy rules.
- [ ] N1.3 Boundaries use IST calendar dates; paid coverage suppresses an irrelevant trial strip.

**N2 — Gap: locked read-only workspace.** Web opts into locked reads and disables mutations. Flutter sends locked stores to BlockedScreen. Mobile API readers also lack allowLockedReadOnly opt-in, so Flutter-only changes are insufficient.

- [ ] N2.1 Lock preserves authorized record reads and shows a persistent warning across applicable screens.
- [ ] N2.2 Sale/status/payment/product/expense/staff/profile mutations are blocked in UI and by the server.
- [ ] N2.3 Queued actions are retained when access is locked and resume safely after unlock; lock must not be mistaken for successful sync or permanent failure warranting data deletion.
- [ ] N2.4 Archive, inactive membership and payment lapse remain separate from administrative lock.

**N3 — Gap: announcements.** Web uses database-backed Server Actions; no matching mobile HTTP endpoint/model/widget found. Web supports targeting, tones, action links, scoped revision-based dismissal, navigation/focus/60-second refresh.

- [ ] N3.1 API derives audience/store from authorized identity, strips targeting details and returns only applicable published notices.
- [ ] N3.2 Native action mapping, info/warning appearance, dismissal and revised-message reappearance work across navigation and account/store switches.
- [ ] N3.3 Unpublish/refresh removes stale online notices; choose explicit offline cache/expiry and dismissal lifetime policies instead of copying browser sessionStorage literally.
- [ ] N3.4 Trial/lock strips remain non-dismissible and coexist with announcements without covering controls, keyboard or sync status.

## Offline regression gate — required for every implementation phase

Keep existing local-first reads, connectivity fallback, optimistic cache updates, store/outlet queue scoping, offline IDs, client action IDs, delta cursors, retry/dead-letter recovery, invoice retry, bootstrap, manual refresh and resume sync. Do not introduce network requests as a prerequisite for ordinary cached screen navigation.

- [ ] F1 Cold start and screen navigation work offline with existing cached data.
- [ ] F2 Offline sale/status/payment and currently supported owner actions persist across app restart.
- [ ] F3 Switch stores/outlets while actions are pending: each action replays against its original authorized scope.
- [ ] F4 Reconnect/retry/timeout does not duplicate orders, payments, expenses, staff or invoice allocation.
- [ ] F5 Cloud refresh does not overwrite pending local edits or lose unsynced identities.
- [ ] F6 Auth/lock/permission failures do not masquerade as offline success, erase queues or trigger unsafe replay.
- [ ] F7 Refresh failures retain cached data with visible error/sync feedback.
- [ ] F8 Default/custom reporting caches retain truthful range/scope labels; native PDF/bill sharing remains available offline.

Existing regression files to retain and extend where necessary: `test/core/local_cache_test.dart`, `test/core/sync_reconciliation_test.dart`, `test/core/app_resume_sync_test.dart`, `test/features/order_offline_id_test.dart`, `test/features/owner_offline_sync_test.dart`, `test/features/owner_bloc_local_first_test.dart`, `test/features/owner_repository_cache_test.dart`, `test/features/sync_per_outlet_test.dart`, `test/features/outlet_access_lost_test.dart`, `test/features/outlet_context_refresh_test.dart`, `test/widgets/outlet_switcher_test.dart`, `test/features/hardened_logout_test.dart`. Listed tests were inspected as coverage locations, not run in this audit.

## Suggested phases

1. Define additive API/access contracts: announcements, lock reads, expense mutations/paid dates, full outlet/profile facts. Reuse backend services and existing employee DTO support.
2. Address staff assignments, expense enhancements and notices with narrow mobile changes and their offline regression gates.
3. Address dashboard models/metric semantics, recent orders, drill-down and outlet views.
4. Add optional invoice-link delivery, profile/payment UX and employee register enhancements.

Each phase should have a reviewed scope and source/API checks, focused existing regressions, and actual iOS/Android checks online/offline with screenshots. Do not claim parity based on compilation or this checklist alone. No implementation, migration, deployment or remote business-data mutation is authorized by this report.
