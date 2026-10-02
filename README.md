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
    --split-debug-info=build/symbols/stage
  ```
  *Output:* `build/app/outputs/bundle/stageRelease/app-stage-release.aab`

* **Production (`com.reddygona.klenpos`)**:
  ```bash
  flutter build appbundle \
    --flavor prod \
    -t lib/main.dart \
    --dart-define=ENV=prod \
    --obfuscate \
    --split-debug-info=build/symbols/prod
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
    --split-debug-info=build/symbols/stage
  ```
  *Output:* `build/app/outputs/flutter-apk/app-stage-release.apk`

* **Production APK**:
  ```bash
  flutter build apk \
    --flavor prod \
    -t lib/main.dart \
    --dart-define=ENV=prod \
    --obfuscate \
    --split-debug-info=build/symbols/prod
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
    --split-debug-info=build/symbols/ios-stage
  ```
  *Output:* `build/ios/ipa/KlenPOS Stage.ipa`

* **Production (`com.reddygona.klenpos`)**:
  ```bash
  flutter build ipa \
    --flavor prod \
    -t lib/main.dart \
    --dart-define=ENV=prod \
    --obfuscate \
    --split-debug-info=build/symbols/ios-prod
  ```
  *Output:* `build/ios/ipa/KlenPOS.ipa`

---

### 3. Local Development & Debugging

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
