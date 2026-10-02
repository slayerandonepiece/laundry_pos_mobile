# KlenPOS — laundry POS mobile app

Flutter app for the store workspace in `../laundry_pos`. "KlenPOS" is the
app display name and branding.

## Start here

| File | What it is |
| --- | --- |
| `prompts/README.md` | How the handoff works, and the design link |
| `TASKS.md` | Phase 2 — the Flutter build |
| `docs/DESIGN-SPEC.md` | Design tokens, metrics, navigation, screen inventory |
| `design/*.dc.html` | The artboards as plain HTML, one file per screen |
| `../laundry_pos/.agents/MOBILE-API-TASKS.md` | Phase 1 — the backend API |

## Approved designs

https://claude.ai/code/artifact/39d574e0-47c8-4b64-aa91-ae4a68d65b40

57 artboards. **v1 (48 screens, left) is approved. v2 (9 screens, far
right) is an exploration and needs sign-off before anyone builds it.**

## Current implementation and next work

The HTTP API and offline-ID sync work are implemented; mobile main includes PR #1 (`cdfc121`). Current context and batch status: `docs/HANDOFF.md`; durable rules: `docs/MEMORY.md`.

Flutter uses four work statuses (Pending, In progress, Ready, Delivered). Android/iOS are the targets. New web enhancements are tracked feature by feature in `docs/WEB-MOBILE-FEATURE-GAPS.md`, with offline regression checks. The audit does not mean those enhancements are implemented.

---

## Build & Release Commands (Copy-Paste Ready)

### Release script

Use `scripts/release.sh` for a guarded stage or production release preparation. It runs the quality gates, builds Android and/or guides the Xcode archive, stores Dart symbols under `$HOME/klenpos-symbols/<env>/<version>/`, uploads Crashlytics symbols, and leaves every store upload manual. Run `scripts/release.sh --help` for flags; use `--dry-run` to inspect the complete flow without building or uploading.

### 1. Android Release Commands (with Obfuscation & R8)

> [!NOTE]
> All release builds automatically apply R8 code/resource shrinking via `proguard-rules.pro` and require signing credentials in `android/key.properties`.

> **Plain HTTP is dev-only.** Only the `dev` flavor may use `http://` (Android: `android/app/src/dev/AndroidManifest.xml` sets `usesCleartextTraffic`; stage and prod are HTTPS-only). In Dart, a `stage` or `prod` build ignores any non-HTTPS `BASE_URL`, and a `--flavor stage|prod` build can never resolve to the `dev` environment even if `--dart-define=ENV=` is missing (`AppEnvironmentConfig`). Android backup is off (`allowBackup="false"`).

#### A. Android App Bundles (`.aab` for Google Play Store)

* **Stage / Beta (`com.reddygona.klenpos.staging`)**:
  ```bash
  flutter build appbundle \
    --flavor stage \
    -t lib/main.dart \
    --dart-define=ENV=stage \
    --obfuscate \
    --split-debug-info="$HOME/klenpos-symbols/stage/<version>/android"
  ```
  *Output:* `build/app/outputs/bundle/stageRelease/app-stage-release.aab`

* **Production (`com.reddygona.klenpos`)**:
  ```bash
  flutter build appbundle \
    --flavor prod \
    -t lib/main.dart \
    --dart-define=ENV=prod \
    --obfuscate \
    --split-debug-info="$HOME/klenpos-symbols/prod/<version>/android"
  ```
  *Output:* `build/app/outputs/bundle/prodRelease/app-prod-release.aab`

---

#### B. Android Release APKs (for Direct Sideloading / Device Testing)

* **Stage / Beta APK**:
  ```bash
  flutter build apk \
    --flavor stage \
    -t lib/main.dart \
    --dart-define=ENV=stage \
    --obfuscate \
    --split-debug-info="$HOME/klenpos-symbols/stage/<version>/android"
  ```
  *Output:* `build/app/outputs/flutter-apk/app-stage-release.apk`

* **Production APK**:
  ```bash
  flutter build apk \
    --flavor prod \
    -t lib/main.dart \
    --dart-define=ENV=prod \
    --obfuscate \
    --split-debug-info="$HOME/klenpos-symbols/prod/<version>/android"
  ```
  *Output:* `build/app/outputs/flutter-apk/app-prod-release.apk`

---

### 2. iOS Release Commands (for TestFlight & App Store)

* **Stage / Beta (`com.reddygona.klenpos.staging`)**:
  ```bash
  flutter build ipa \
    --flavor stage \
    -t lib/main.dart \
    --dart-define=ENV=stage \
    --obfuscate \
    --split-debug-info="$HOME/klenpos-symbols/stage/<version>/ios"
  ```
  *Output:* `build/ios/ipa/KlenPOS Stage.ipa`

* **Production (`com.reddygona.klenpos`)**:
  ```bash
  flutter build ipa \
    --flavor prod \
    -t lib/main.dart \
    --dart-define=ENV=prod \
    --obfuscate \
    --split-debug-info="$HOME/klenpos-symbols/prod/<version>/ios"
  ```
  *Output:* `build/ios/ipa/KlenPOS.ipa`

---

### 3. Upload symbols to Crashlytics (after every stage/prod release build)

Releases are built with `--obfuscate`, so Crashlytics shows unreadable stack traces until symbols are uploaded. **Android** uses the folder passed to `--split-debug-info` and the Firebase CLI. **iOS** uses the archive's dSYMs and Firebase's `upload-symbols` tool: the CLI's `crashlytics:symbols:upload` cannot read iOS `.symbols` files (it fails with "Breakpad symbol generation failed"). Run the matching command right after the build, from the repo root, and keep the symbol folders for every released version.

| Build | Symbol folder | Command |
| --- | --- | --- |
| Android stage | `$HOME/klenpos-symbols/stage/<version>/android` | `firebase crashlytics:symbols:upload --app=<id from stage google-services.json> "$HOME/klenpos-symbols/stage/<version>/android"` |
| Android prod | `$HOME/klenpos-symbols/prod/<version>/android` | `firebase crashlytics:symbols:upload --app=<id from prod google-services.json> "$HOME/klenpos-symbols/prod/<version>/android"` |

**iOS** (after Product > Archive in Xcode; this picks the newest Xcode archive, so check it is the one you just made):

```bash
# stage
build/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols -gsp ios/Firebase/stage/GoogleService-Info.plist -p ios "$(ls -dt ~/Library/Developer/Xcode/Archives/*/*.xcarchive | head -1)/dSYMs"
# prod
build/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols -gsp ios/Firebase/prod/GoogleService-Info.plist -p ios "$(ls -dt ~/Library/Developer/Xcode/Archives/*/*.xcarchive | head -1)/dSYMs"
```

(For a `flutter build ipa` archive the dSYMs are in `build/ios/archive/Runner.xcarchive/dSYMs` instead.)

If `build/ios/SourcePackages` is missing (after `flutter clean`), run any `flutter build ios` once or use the same tool under `~/Library/Developer/Xcode/DerivedData/Runner-*/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols`. The important file is `App.framework.dSYM` (the Dart code); its UUID must match `dwarfdump --uuid "$HOME/klenpos-symbols/<flavor>/<version>/ios/app.ios-arm64.symbols"`.

The Android app IDs are the `mobilesdk_app_id` of each flavor's `google-services.json` (package `com.reddygona.klenpos.staging` / `com.reddygona.klenpos`). The iOS commands read the app ID from `ios/Firebase/<flavor>/GoogleService-Info.plist`.

- The Crashlytics Gradle plugin already uploads Android native symbols; this step is for the Dart code.
- When building from Xcode (Product > Archive), run `flutter build ios --release --config-only --flavor <stage|prod> --dart-define=ENV=<stage|prod> --obfuscate --split-debug-info="$HOME/klenpos-symbols/<stage|prod>/<version>/ios"` first. After archiving, upload the dSYMs from that archive (Organizer > Show in Finder > Show Package Contents > dSYMs) with the iOS command above, pointing at that folder.
- Xcode's "Upload Symbols Failed ... FirebaseAnalytics / GoogleAppMeasurement / GoogleAdsOnDeviceConversion / GoogleAppMeasurementIdentitySupport" messages are harmless warnings: those are Google's closed-source binaries and ship without dSYMs. They do not block the upload.

### 4. Release checklist (stage first, then prod; same steps for both)

Replace `<flavor>` with `stage` or `prod` and `<version>` with the full `name+build` value. Symbols stay outside the repository so `flutter clean` cannot delete them. Keep every released version's folder.

**Common (both platforms)**
1. **Version.** Bump `version:` in `pubspec.yaml` (`name+build`). The build number must be higher than anything already uploaded to Play Console / App Store Connect. Commit it.
2. **Clean gate.** `flutter clean && flutter pub get && dart format . && flutter analyze && flutter test` (analyze clean, all tests pass).

**Android (Google Play)**
1. Build the bundle:
   `flutter build appbundle --flavor <flavor> -t lib/main.dart --dart-define=ENV=<flavor> --obfuscate --split-debug-info="$HOME/klenpos-symbols/<flavor>/<version>/android"`
2. Upload the Dart symbols to Crashlytics (section 3, Android row): `firebase crashlytics:symbols:upload --app=<android app id> "$HOME/klenpos-symbols/<flavor>/<version>/android"`.
3. In Play Console upload `build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab`: Testing > Internal testing for stage, Production for prod. Paste the "What's new" text (max 500 characters).

**iOS (App Store Connect), always from Xcode**
1. Prepare the Flutter config so Xcode builds with the right flavor, environment and obfuscation:
   `flutter build ios --release --config-only --flavor <flavor> --dart-define=ENV=<flavor> --obfuscate --split-debug-info="$HOME/klenpos-symbols/<flavor>/<version>/ios"`
2. `open ios/Runner.xcworkspace` (the workspace, not the project).
3. In Xcode pick the `<flavor>` scheme and the destination **Any iOS Device (arm64)**. Under Signing & Capabilities check team `CARPPQWPK9` and "Automatically manage signing".
4. **Product > Archive.** Organizer opens when it finishes. The archive is saved under `~/Library/Developer/Xcode/Archives/<date>/` (not `build/ios/archive`).
5. Upload the dSYMs of that archive to Crashlytics (section 3, iOS command, pointing at the newest Xcode archive).
6. In Organizer: **Validate App**, then **Distribute App > App Store Connect > Upload**. "Upload Symbols Failed" for FirebaseAnalytics, GoogleAppMeasurement, GoogleAdsOnDeviceConversion and GoogleAppMeasurementIdentitySupport is a harmless warning.
7. In App Store Connect: wait for processing (about 10-30 minutes), answer export compliance (standard HTTPS only), attach the build to the version and paste "What's new". Stage goes to TestFlight only; prod: check screenshots and privacy answers, add a demo owner login to the review notes, then Submit for Review.
   Upload only one build per version+build number (App Store Connect rejects a duplicate).

**After release**
Tag the commit (`git tag v<version>`) and push the tag.

### 5. Local Development & Debugging

* **Run Dev (local emulator/device)**:
  ```bash
  flutter run --flavor dev -t lib/main.dart --dart-define=ENV=dev
  ```
* **Run Stage**:
  ```bash
  flutter run --flavor stage -t lib/main.dart --dart-define=ENV=stage
  ```
* **Run Prod**:
  ```bash
  flutter run --flavor prod -t lib/main.dart --dart-define=ENV=prod
  ```

---

## Note

`.claude/launch.json` starts the **web** app (`npm --prefix ../laundry_pos run dev`) for design-parity checks. It is not used by the Flutter build; delete it if you find it confusing.
