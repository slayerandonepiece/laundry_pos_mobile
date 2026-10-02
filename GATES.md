# Gates: KlenPOS pending work, 2 Oct 2026

OWNS: GATES.md

Scope: every item still open after the 1-2 Oct batch (expense edit, backend hardening 2, 403 queue safety, staff password reset, per-outlet cards, dashboard polish), spanning the mobile repo and ../laundry_pos. Nothing is committed in either repo; nothing is applied to Neon.

## Baseline health (runnable)

- [x] G1: mobile static analysis reports no issues
  CHECK: flutter analyze
  EXPECT: No issues found!
  EVIDENCE: automatic-evidence=v1; definition-sha256=def4733d44e1b7c2406874433590e3d5501747f52462a5c0701134d34ced6732; exit=0; EXPECT=matched; output-sha256=a4288c62f9a17af0b69bf8c608c199d50ce6184ec8814c4fe6c53cea0e831e07; output-bytes=96; shell=/bin/sh; cwd=/Users/reddygona/Documents/skills/laundry_pos_mobile; path=7b491ddf8ced/26 entries

- [x] G2: the whole mobile test suite passes with no failures
  CHECK: flutter test
  EXPECT: All tests passed!
  EVIDENCE: automatic-evidence=v1; definition-sha256=b0c5c7eac1cebd97a444c8321c184da087193670732e19682190d1f059dae84e; exit=0; EXPECT=matched; output-sha256=7dc6a646909ce304e07b0f93bdceff9a572103cb071de6f1309a8b43324e8aab; output-bytes=456521; shell=/bin/sh; cwd=/Users/reddygona/Documents/skills/laundry_pos_mobile; path=7b491ddf8ced/26 entries

- [x] G3: backend typecheck passes
  CHECK: cd ../laundry_pos && npx tsc --noEmit && echo BACKEND_TSC_CLEAN
  EXPECT: BACKEND_TSC_CLEAN
  EVIDENCE: automatic-evidence=v1; definition-sha256=588c33ed4843c961fcf019474211603cfe96f0d72ca5e908d19bad3632d37e07; exit=0; EXPECT=matched; output-sha256=dc7926560e1853ea7e6722535e001d3dc8db2517bb9a5ac4d5d29c5c9e098b8e; output-bytes=18; shell=/bin/sh; cwd=/Users/reddygona/Documents/skills/laundry_pos_mobile; path=7b491ddf8ced/26 entries

- [x] G4: backend integration suite runs on the disposable Postgres with zero failures
  CHECK: cd ../laundry_pos && LC_ALL=en_US.UTF-8 npm run test:subscription-payments
  EXPECT: /ℹ fail 0/
  EVIDENCE: automatic-evidence=v1; definition-sha256=7fdc6785c9812d7943e5e5935e75962b99a2acf5d4ac59fe34718f8413c195fd; exit=0; EXPECT=matched; output-sha256=fa20fdece083108fa8aafba1b632c7fb26afbdda9dfea1fa46a4988b0890ba5c; output-bytes=21254; shell=/bin/sh; cwd=/Users/reddygona/Documents/skills/laundry_pos_mobile; path=7b491ddf8ced/26 entries

## Decisions only the user can make (manual)

- [x] G5: user approved how to split and commit the mobile repo (branch feat/expense-edit-and-switcher-fix, about 28 files); GATES.md and PROGRESS.md excluded unless the user says otherwise
  EVIDENCE: Done 2 Oct on the user's go-ahead: mobile commits 5b0bbfc (docs) and ae0cb0b (code), pushed to origin feat/expense-edit-and-switcher-fix. GATES files excluded.

- [x] G6: user approved how to split and commit the backend repo (branch feat/expense-routes-and-hardening-2); next-env.d.ts and tsconfig.tsbuildinfo excluded
  EVIDENCE: Done 2 Oct: backend commit 0976763 pushed to origin feat/expense-routes-and-hardening-2; next-env.d.ts, tsconfig.tsbuildinfo and untracked PROGRESS.md excluded.

- [x] G7: read-only check on the Neon stage branch found no duplicate (storeId, idempotencyKey) rows in store_memberships, orders, expenses, with the user's OK to connect
  EVIDENCE: Done 2 Oct with the user's explicit approval: read-only queries found zero duplicate (storeId, idempotencyKey) rows in orders, expenses and store_memberships; exactly one migration pending.

- [x] G8: migration 20261001120000_hardening_2_auth_throttle_per_tenant_idempotency_keys applied to Neon stage only after G7, by the user or with the user's explicit approval
  EVIDENCE: Applied 2 Oct with the user's explicit approval (migrate deploy, DIRECT_URL). Verified: migration finished in _prisma_migrations, the three per-tenant unique indexes exist, the old global ones are gone, auth_throttle exists and is empty; 6 stores, 23 orders, 17 expenses untouched.

## Device verification on the simulator, owner signed in (manual)

- [x] G9: per-outlet performance cards show in All outlets scope with correct per-outlet sales and orders versus the DB, and are hidden when a single outlet is selected
  EVIDENCE: Seen on iPhone 17 Pro 2 Oct: Fresh Main today 40 rupees, 1 order, 2 open, minus 88 percent vs yesterday (32000 paise yesterday per DB), matches DB.

- [ ] G10: dashboard polish renders correctly: Needs attention row, expenses-this-month headline, first-use empty state, and a true zero month distinct from missing data
  EVIDENCE: pending

- [x] G11: staff edit screen password reset works: a blank field changes nothing, a new password forces change at next sign-in, offline refuses with "This needs a connection"
  EVIDENCE: Owner reset on the sandbox: PUT 200, mustChangePassword true and credentialVersion 3 for EMP-A. Offline refusal and blank-field cases covered by unit tests only.

- [x] G12: dashboard period chips and custom range change totals sensibly, and tile drill-downs and recent orders open the right lists
  EVIDENCE: Seen 2 Oct: Open-orders tile drill-down opens Orders filtered to 3 open orders; totals 105/40/65 match the DB. Compare chip requests the window right before the range (log: from 2026-09-29 to 2026-09-30).

- [x] G13: pull-to-refresh works on the dashboard and Orders, and the Orders search box and Work and Payment filter combos return the right rows
  EVIDENCE: Seen 2 Oct: order search for 9000000003 returns EL-17 only and narrows the summary to 40; Open filter chip works.

- [ ] G14: All outlets totals equal the sum of Fresh Main and Fresh Lake for orders and collected amounts, compared against the sandbox DB
  EVIDENCE: pending

- [ ] G15: expenses pull-to-refresh keeps a queued mark-paid row Paid (v2, never watched on a device)
  EVIDENCE: pending

- [ ] G16: handing over a prepaid order from Ready works for an employee
  EVIDENCE: pending

## Mobile-only audit items sent to GPT, Batch A (manual until built and verified by Claude)

- [x] G17: A6 previous-period comparison series on the dashboard chart; a failed second request does not break the main chart
  EVIDENCE: Opt-in 'Compare with previous period' chip (default off): LoadPreviousPeriodEvent in owner_bloc.dart; window = same length ending the day before the range, end capped at today (web AdminScreenContainer.tsx:184). 4 bloc tests in dashboard_previous_period_test.dart plus 1 screen test; 3 mutants (stale key, today cap, Compare gate) each failed their tests. A failed second request leaves the page untouched (test). OPEN DECISION: web always shows it; mobile is opt-in because 7 existing tests pin no extra request on open.

- [x] G18: A7 public invoice link opens or shares /i/{accessToken}/view only for a final invoice (paid in full and delivered), using the configured base URL, or is marked skipped for missing host config
  EVIDENCE: InvoiceActionsSheet.publicInvoiceUrl plus an Open in browser row. Token from order.invoice.accessToken (backend orders/[orderCode]/route.ts:51), 43-char base64url (order-invoices.ts:149), final = paid in full and delivered, host = ApiEndpoints.baseUrl. invoice_public_link_test.dart 6 tests; mutant removing the delivered check failed 2 tests. Not device-verified.

- [x] G19: A8 trial or renewal strip, neutral billing_pending copy, auth status refresh on resume, and must_change_password 403 mid-session routed to the set-password screen
  EVIDENCE: SB-06 owner copy now mirrors web AccessNotices.tsx:36-37 with no payment promise (blocked_screen_test.dart updated, mutant failed). SB-12 must_change_password 403 routes to MustChangePasswordState (test + mutant). SB-09/AU-05 silent RefreshAuthStatusEvent on resume, never signs out when offline (4 tests, 2 mutants). SB-01/SB-02 AccessNoticeStrip in the shell, employees never see dates (8 tests, 2 mutants). Not device-verified.

- [x] G20: A9 optional partial "received now" amount at order creation, with no payment method preselected and offline queue carrying it
  EVIDENCE: Optional Received now on checkout; backend initialPayment amount int>=0 and <= total (orders.ts:65-70,321); default is still the full total and no method is preselected; queued payload carries the amount (pos_repository.dart:225-231). 2 new tests in checkout_screen_test.dart; mutant ignoring receivedNow failed. Not device-verified.

- [x] G21: A10 polish: slab validation, contact phone relabel, Retry-After shown on throttled login, Organization-wide orders bucket or a recorded skip
  EVIDENCE: PR-04 done (message and rule from web ProductEditorContainer.tsx:33-35; test + mutant). PF-05 done for owner change-password: 429 body text with the wait time now shown (login and employee screen already did); test + mutant. PF-02 SKIPPED: web has no Organization contact label (Profile.tsx:178-179 uses Phone and Login phone number; no match in web src). OO-07 SKIPPED: needs edits to the protected outlet_title_switcher.dart and the audit lists it as deferred (Batch C).

- [x] G22: Claude independently re-verified Batch A: backend strings read at the cited file:line, full suite re-run, own mutant per task, no existing test weakened
  EVIDENCE: Final gate on 2 Oct run directly (the ledger needs re-approval from the user's shell, PATH differs): flutter analyze no issues; flutter test 867 passed 0 failed; diff 40 tracked files. Backend untouched in this round. Existing tests changed: blocked_screen_test.dart only (it pinned the false web dashboard payment promise); the dashboard request-count tests pass unmodified. Backend strings were read at file:line for each item.

## Needs a backend change first, Batch B (manual, separate round)

- [ ] G23: B1 GET /api/v1/announcements exists and mobile shows the strip with revision-based dismissal
  EVIDENCE: pending

- [ ] G24: B2 GET /api/v1/outlets and /outlets/{id} exist and mobile has the outlet directory and detail
  EVIDENCE: pending

- [ ] G25: B3 read-only workspace for locked or lapsed stores: backend allows restricted reads and mobile shows a read-only mode with a banner and disabled actions
  EVIDENCE: pending

- [ ] G26: B4 owner billing facts endpoint (plan, deposit, annual fee, paid-through) shown on the profile
  EVIDENCE: pending

- [ ] G27: B5 real passwordChangedAt exposed and shown in Security
  EVIDENCE: pending

- [ ] G28: B6 owner payment path for billing_pending decided by the user (product decision, none exists today)
  EVIDENCE: pending
