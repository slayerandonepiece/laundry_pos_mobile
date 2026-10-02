# Gates: KlenPOS release observability and automation

OWNS: lib/core/error/crash_context.dart, lib/core/analytics/app_analytics.dart, lib/core/network/firebase_service.dart, lib/main.dart, lib/shared/widgets/app_version_text.dart, lib/features/**, test/core/error/crash_context_test.dart, test/core/analytics/app_analytics_test.dart, test/widgets/app_version_text_test.dart, android/app/proguard-rules.pro, scripts/release.sh, README.md, docs/HANDOFF.md

Scope: Add privacy-safe crash context, analytics and diagnostics, prepare tighter stage R8 rules, and add a guarded dry-run-tested release script.

- [x] A: crash context sets only opaque identifiers and required keys, and clears on unauthenticated states
  CHECK: flutter test test/core/error/crash_context_test.dart
  EXPECT: All tests passed!
  EVIDENCE: 3 tests passed. Mutation changed role normalization to lowercase; owner and employee assertions failed, then passed after restoration.

- [x] B: analytics wrapper and required event helpers emit exact PII-free payloads and safely no-op without Firebase
  CHECK: flutter test test/core/analytics/app_analytics_test.dart
  EXPECT: All tests passed!
  EVIDENCE: 2 tests passed. Mutation renamed payment_recorded; the exact-name assertion failed, then passed after restoration.

- [x] C: non-production diagnostics dialog is gated by environment and all injected actions are covered
  CHECK: flutter test test/widgets/app_version_text_test.dart
  EXPECT: All tests passed!
  EVIDENCE: 8 tests passed. Mutation inverted the production gate; four widget tests failed, then all passed after restoration.

- [x] D: tightened ProGuard rules build the arm64 stage release without missing-class failures
  CHECK: zsh -lc 'mkdir -p /private/tmp/klenpos-release-gate/android && flutter build apk --release --flavor stage --target-platform android-arm64 --obfuscate --split-debug-info=/private/tmp/klenpos-release-gate/android && echo "stage r8 gate passed"'
  EXPECT: stage r8 gate passed
  EVIDENCE: Final build succeeded: app-stage-release.apk (22.4MB). No missing-class warning. DEX measurements: baseline 3,721,848; without Flutter blanket keeps 3,177,968; without Firebase blanket keep 2,674,008 bytes.

- [x] E: release script parses and its confirmed stage dry run completes without building or uploading
  CHECK: zsh -lc 'bash -n scripts/release.sh && scripts/release.sh --platform both --env stage --dry-run --yes'
  EXPECT: DRY RUN COMPLETE
  EVIDENCE: bash -n exited 0; dry run printed both platform flows and ended DRY RUN COMPLETE. shellcheck is not installed.

- [x] F: Flutter static analysis is clean
  CHECK: flutter analyze
  EXPECT: No issues found
  EVIDENCE: No issues found! (ran in 3.0s)

- [x] G: complete Flutter test suite passes
  CHECK: flutter test
  EXPECT: All tests passed!
  EVIDENCE: 00:29 +898: All tests passed!

- [x] H: no-codesign obfuscated stage iOS release builds with symbols outside the repository
  CHECK: zsh -lc 'mkdir -p /private/tmp/klenpos-release-gate/ios && flutter build ios --release --no-codesign --flavor stage --obfuscate --split-debug-info=/private/tmp/klenpos-release-gate/ios && echo "stage ios gate passed"'
  EXPECT: stage ios gate passed
  EVIDENCE: Xcode build done in 39.6s; built build/ios/iphoneos/Runner.app (26.7MB).

- [x] I: repository formatting is stable after the required whole-tree formatter pass
  CHECK: dart format --output=none --set-exit-if-changed .
  EXPECT: Changed 0 files
  EVIDENCE: Formatted 267 files (0 changed) in 1.19 seconds.
