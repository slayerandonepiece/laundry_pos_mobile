# Gates: Mobile-only parity audit Batch A (A6-A10)

OWNS: lib/core/network/dio_interceptors.dart, lib/features/auth/bloc/auth_bloc.dart, lib/main.dart, lib/shared/widgets/blocked_screen.dart, lib/features/shell/presentation/main_navigation_shell.dart, lib/features/owner/data/owner_repository.dart, lib/features/owner/bloc/owner_bloc.dart, lib/features/owner/bloc/owner_state.dart, lib/features/owner/presentation/owner_dashboard_screen.dart, lib/features/orders/presentation/invoice_actions_sheet.dart, lib/features/pos/bloc/cart_bloc.dart, lib/features/pos/presentation/checkout_screen.dart, lib/features/owner/presentation/services_screen.dart, lib/features/owner/presentation/owner_profile_screen.dart, test/features/**

Scope: implement remaining mobile-only parity audit items (A6: D-06, A7: INV-06, A8: SB-01, SB-02, SB-06, SB-09, SB-12, AU-05, A9: POS-08, A10: PR-04, PF-02, PF-05, OO-07) with strict contract proof and zero regressions.

- [ ] G1: D-06 previous-period comparison series renders on dashboard chart
  CHECK: flutter test test/features/dashboard_previous_period_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G2: INV-06 public invoice link is generated only for final orders
  CHECK: flutter test test/features/invoice_public_link_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G3: SB-01 trial status strip renders role-differentiated message
  CHECK: flutter test test/features/trial_status_strip_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G4: SB-02 pre-expiry renewal warning strip renders 7 days before expiry
  CHECK: flutter test test/features/renewal_warning_strip_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G5: SB-06 billing_pending copy is neutral without false payment promise
  CHECK: flutter test test/features/billing_pending_copy_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G6: SB-09 auth status refreshes on application resume
  CHECK: flutter test test/features/auth_status_resume_refresh_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G7: SB-12 must_change_password 403 mid-session routes to set-password screen
  CHECK: flutter test test/features/must_change_password_mid_session_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G8: AU-05 user session and subscription state refresh on resume
  CHECK: flutter test test/features/session_resume_refresh_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G9: POS-08 partial received now amount is accepted and queued at order creation
  CHECK: flutter test test/features/checkout_partial_payment_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G10: PR-04 slab tiers reject non-increasing limits and non-positive prices
  CHECK: flutter test test/features/slab_validation_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G11: PF-02 editable contact phone is labelled Organization contact
  CHECK: flutter test test/features/profile_contact_phone_label_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G12: PF-05 throttled login surfaces retry interval to user
  CHECK: flutter test test/features/throttled_login_retry_after_test.dart
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] G13: OO-07 organization-wide bucket in owner Orders scope for null-outlet orders
  EVIDENCE: pending

- [ ] M1: D-06 mutation check proves previous-period test fails when second request is omitted
  EVIDENCE: pending

- [ ] M2: INV-06 mutation check proves invoice link test fails when link is allowed for non-final orders
  EVIDENCE: pending

- [ ] M3: SB-01 mutation check proves trial strip test fails when owner details are hidden
  EVIDENCE: pending

- [ ] M4: SB-02 mutation check proves renewal warning test fails when 7-day threshold is ignored
  EVIDENCE: pending

- [ ] M5: SB-06 mutation check proves billing_pending test fails when false web payment promise is restored
  EVIDENCE: pending

- [ ] M6: SB-09 mutation check proves resume refresh test fails when CheckAuthStatusEvent is not sent on resume
  EVIDENCE: pending

- [ ] M7: SB-12 mutation check proves must_change_password test fails when 403 routes to BlockedScreen
  EVIDENCE: pending

- [ ] M8: AU-05 mutation check proves session resume test fails when subscription update on resume is ignored
  EVIDENCE: pending

- [ ] M9: POS-08 mutation check proves partial payment test fails when partial amount is ignored
  EVIDENCE: pending

- [ ] M10: PR-04 mutation check proves slab validation test fails when non-monotonic limits are accepted
  EVIDENCE: pending

- [ ] M11: PF-02 mutation check proves phone label test fails when editable phone is labelled PHONE
  EVIDENCE: pending

- [ ] M12: PF-05 mutation check proves retry interval test fails when retry seconds are not shown
  EVIDENCE: pending

- [ ] M13: contract strings are verified against backend source file and line
  EVIDENCE: pending

- [ ] F1: dart format reports no changes needed on modified files
  CHECK: dart format --set-exit-if-changed lib/core/network/dio_interceptors.dart lib/features/auth/bloc/auth_bloc.dart lib/main.dart lib/shared/widgets/blocked_screen.dart lib/features/shell/presentation/main_navigation_shell.dart lib/features/owner/data/owner_repository.dart lib/features/owner/bloc/owner_bloc.dart lib/features/owner/bloc/owner_state.dart lib/features/owner/presentation/owner_dashboard_screen.dart lib/features/orders/presentation/invoice_actions_sheet.dart lib/features/pos/bloc/cart_bloc.dart lib/features/pos/presentation/checkout_screen.dart lib/features/owner/presentation/services_screen.dart lib/features/owner/presentation/owner_profile_screen.dart test/features/dashboard_previous_period_test.dart test/features/invoice_public_link_test.dart test/features/trial_status_strip_test.dart test/features/renewal_warning_strip_test.dart test/features/billing_pending_copy_test.dart test/features/auth_status_resume_refresh_test.dart test/features/must_change_password_mid_session_test.dart test/features/session_resume_refresh_test.dart test/features/checkout_partial_payment_test.dart test/features/slab_validation_test.dart test/features/profile_contact_phone_label_test.dart test/features/throttled_login_retry_after_test.dart
  EXPECT: (0 changed)
  EVIDENCE: pending

- [ ] F2: static analysis reports no issues across the codebase
  CHECK: flutter analyze
  EXPECT: No issues found!
  EVIDENCE: pending

- [ ] F3: whole flutter test suite passes
  CHECK: flutter test
  EXPECT: All tests passed!
  EVIDENCE: pending

- [ ] F4: working directory git status lists modified and untracked files
  CHECK: git status --short
  EXPECT: /M\s+lib\//
  EVIDENCE: pending

ABANDON: G13 The owner Orders scope switcher is implemented by lib/shared/widgets/outlet_title_switcher.dart (which is hard-ruled off-limits for editing and tied to OutletScopeCubit's allOutlets/activeOutletId binary state). Adding an 'Organization-wide' (null-outlet) scope to the header switcher without modifying outlet_title_switcher.dart is impossible; audit Batch C also classifies OO-07's multi-select/bucket as intentionally deferred simplification.
