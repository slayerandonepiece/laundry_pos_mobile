# KlenPOS — App Icon, Native Splash & Firebase Setup

Reference guide for wiring the finalized brand assets (see `assets/icons/` and
`assets/branding/`) into the iOS/Android native projects, and for setting up
Firebase across dev/stage/prod.

- App name: **KlenPOS**
- Bundle ID / applicationId: `com.reddygona.klenpos` (prod), `com.reddygona.klenpos.dev`, `com.reddygona.klenpos.staging`
- Palette: Electric Cyan `#00D4FF`, Crisp Mint `#4CFFB3`, Deep Hydro `#0A2540`, Clean Obsidian `#0B0F14`

---

## 1. Add App Icon

### iOS

Source file: `assets/icons/klenpos_appicon_ios_1024.png` (1024×1024, no alpha — verified).

Run from the project root. `sips` is built into macOS — no package needed —
and generates every size Xcode's `Contents.json` expects, overwriting the
placeholder icons in place:

```bash
cd ios/Runner/Assets.xcassets/AppIcon.appiconset
SRC=../../../../assets/icons/klenpos_appicon_ios_1024.png

sips -z 1024 1024 "$SRC" --out Icon-App-1024x1024@1x.png
sips -z 20 20     "$SRC" --out Icon-App-20x20@1x.png
sips -z 40 40     "$SRC" --out Icon-App-20x20@2x.png
sips -z 60 60     "$SRC" --out Icon-App-20x20@3x.png
sips -z 29 29     "$SRC" --out Icon-App-29x29@1x.png
sips -z 58 58     "$SRC" --out Icon-App-29x29@2x.png
sips -z 87 87     "$SRC" --out Icon-App-29x29@3x.png
sips -z 40 40     "$SRC" --out Icon-App-40x40@1x.png
sips -z 80 80     "$SRC" --out Icon-App-40x40@2x.png
sips -z 120 120   "$SRC" --out Icon-App-40x40@3x.png
sips -z 120 120   "$SRC" --out Icon-App-60x60@2x.png
sips -z 180 180   "$SRC" --out Icon-App-60x60@3x.png
sips -z 76 76     "$SRC" --out Icon-App-76x76@1x.png
sips -z 152 152   "$SRC" --out Icon-App-76x76@2x.png
sips -z 167 167   "$SRC" --out Icon-App-83.5x83.5@2x.png
```

Then open `ios/Runner.xcworkspace` in Xcode → `Assets.xcassets` → `AppIcon`
and confirm every slot shows the new K icon (no yellow warning triangles =
correct sizes).

### Android

Simple path — flat launcher icon, works on every Android version:

```bash
cd android/app/src/main/res
SRC=../../../../../../assets/icons/klenpos_appicon_legacy_512.png

sips -z 48 48   "$SRC" --out mipmap-mdpi/ic_launcher.png
sips -z 72 72   "$SRC" --out mipmap-hdpi/ic_launcher.png
sips -z 96 96   "$SRC" --out mipmap-xhdpi/ic_launcher.png
sips -z 144 144 "$SRC" --out mipmap-xxhdpi/ic_launcher.png
sips -z 192 192 "$SRC" --out mipmap-xxxhdpi/ic_launcher.png
```

**Optional but recommended — adaptive icon** (the squircle/circle shape on
newer Android launchers), using the already-generated foreground/background
layers:

```bash
mkdir -p mipmap-anydpi-v26
cat > mipmap-anydpi-v26/ic_launcher.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
EOF

FG=../../../../../../assets/icons/klenpos_adaptive_foreground_432.png
BG=../../../../../../assets/icons/klenpos_adaptive_background_432.png

sips -z 108 108 "$FG" --out mipmap-mdpi/ic_launcher_foreground.png
sips -z 162 162 "$FG" --out mipmap-hdpi/ic_launcher_foreground.png
sips -z 216 216 "$FG" --out mipmap-xhdpi/ic_launcher_foreground.png
sips -z 324 324 "$FG" --out mipmap-xxhdpi/ic_launcher_foreground.png
cp "$FG" mipmap-xxxhdpi/ic_launcher_foreground.png

sips -z 108 108 "$BG" --out mipmap-mdpi/ic_launcher_background.png
sips -z 162 162 "$BG" --out mipmap-hdpi/ic_launcher_background.png
sips -z 216 216 "$BG" --out mipmap-xhdpi/ic_launcher_background.png
sips -z 324 324 "$BG" --out mipmap-xxhdpi/ic_launcher_background.png
cp "$BG" mipmap-xxxhdpi/ic_launcher_background.png
```

Then `flutter run` (or reinstall). Android caches launcher icons
aggressively — uninstall the old app from the device/emulator first if it
doesn't refresh.

---

## 2. Native Splash Without a Package

### Android

Edit these two files (both already exist in the project):

**Superseded note:** the native splash was later corrected to a plain
white background with just the logo (not a colored canvas). The steps
below reflect the **current, correct** setup: white background + the
transparent `klenpos_adaptive_foreground_432.png` logo, not a baked-in
colored splash image. The original `klenpos_splash_android.png` /
`klenpos_splash_ios.png` assets referenced in an earlier draft of this
doc have been removed as unused.

`android/app/src/main/res/drawable/launch_background.xml` (light mode):

```xml
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/white"/>
    <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/launch_image" />
    </item>
</layer-list>
```

`android/app/src/main/res/drawable-v21/launch_background.xml` — same
content.

Drop in the logo image (`nodpi` so Android doesn't rescale it per
density) — use the transparent adaptive-icon foreground, not a colored
splash canvas:

```bash
mkdir -p android/app/src/main/res/mipmap-nodpi
cp assets/icons/klenpos_adaptive_foreground_432.png android/app/src/main/res/mipmap-nodpi/launch_image.png
```

### iOS

No package needed — edit `ios/Runner/Base.lproj/LaunchScreen.storyboard`
and its image asset directly.

1. Replace the launch image asset (already wired into the storyboard as
   `LaunchImage`) with the transparent logo, not a colored splash canvas:

```bash
cd ios/Runner/Assets.xcassets/LaunchImage.imageset
SRC=../../../../../assets/icons/klenpos_adaptive_foreground_432.png
sips -z 168 185  "$SRC" --out LaunchImage.png
sips -z 336 370  "$SRC" --out LaunchImage@2x.png
sips -z 504 555  "$SRC" --out LaunchImage@3x.png
```

   These dimensions match the placeholder's declared canvas size
   (168×185pt) in the storyboard. If the splash art has different
   proportions, open Xcode and resize the image view instead of forcing
   this aspect ratio.

2. Change the background color from white to Deep Hydro — in
   `ios/Runner/Base.lproj/LaunchScreen.storyboard`, change:

```xml
<color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
```

   to:

```xml
<color key="backgroundColor" red="0.0392" green="0.1451" blue="0.2510" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
```

   (`#0A2540` in 0–1 RGB.)

3. Open `ios/Runner.xcworkspace` in Xcode once to let it re-index the
   storyboard, then run on a simulator to confirm the splash looks right.
   Xcode won't auto-scale the imageView's frame — you may need to open the
   storyboard visually and resize the image view, since
   `contentMode="center"` doesn't scale to fit.

---

## 3. Firebase Setup (dev / stage / prod × Android / iOS)

Firebase needs 6 total app registrations — 3 environments × 2 platforms —
each with its own Firebase project so dev/stage crash reports and analytics
don't pollute production data.

### Can Gemini do this via MCP?

Not knowable from this session — MCP servers configured in a Gemini
session are local to that session. Google publishes an official Firebase
MCP server (`firebase-tools experimental:mcp`); if it's wired into Gemini
the same way Stitch was wired into this session, Gemini can create/configure
Firebase projects directly. The prompt below checks for that and falls back
to a manual console walkthrough if it's not available.

### Prompt for Gemini

```
I need Firebase set up for a Flutter app called KlenPOS, with separate
environments for dev/stage/prod, on both Android and iOS.

FIRST: check whether you have any Firebase-related MCP tools available
(e.g. a firebase-tools MCP server, project/app creation, config-fetching
tools). Tell me explicitly whether you do or don't before proceeding.

IF you have Firebase MCP tools available:
- Ask me for the required inputs before creating anything: my Google
  Cloud/Firebase account or org (if applicable), preferred project ID
  naming (I suggest klenpos-dev, klenpos-stage, klenpos-prod — confirm
  availability), and billing account if Blaze plan is required for any
  feature.
- Use the MCP tools to create the 3 Firebase projects, register the
  Android app (applicationId com.reddygona.klenpos, with .dev/.staging
  suffixes) and iOS app (bundle ID com.reddygona.klenpos, with .dev/.staging
  suffixes) in each project, enable Crashlytics, Analytics, Cloud
  Messaging, and Remote Config on each, and fetch the resulting
  google-services.json / GoogleService-Info.plist for each of the 3
  environments directly.
- Flag anything you cannot do via MCP (e.g. uploading an APNs auth key for
  iOS push, which requires an Apple Developer account action) as a manual
  step for me.

IF you do NOT have Firebase MCP tools available:
- Give me a precise, numbered, step-by-step manual guide for the Firebase
  console (https://console.firebase.google.com) to:
  1. Create 3 separate projects: klenpos-dev, klenpos-stage, klenpos-prod
  2. In each project, register an Android app with applicationId
     com.reddygona.klenpos.dev / com.reddygona.klenpos.staging /
     com.reddygona.klenpos (prod), and an iOS app with bundle ID
     com.reddygona.klenpos.dev / com.reddygona.klenpos.staging /
     com.reddygona.klenpos (prod)
  3. Enable Crashlytics, Analytics, Cloud Messaging, Remote Config in each
     project
  4. Download google-services.json and GoogleService-Info.plist for each
     of the 3 environments
  5. Tell me exactly what to do with the APNs auth key for Cloud Messaging
     on iOS (Apple Developer account step)
- Tell me exactly which file goes where once downloaded, matching this
  project's existing flavor structure: Android flavors are dev/stage/prod
  (android/app/build.gradle.kts), iOS schemes are
  Debug/Release/Profile-{dev,stage,prod}
  (ios/Runner.xcodeproj/project.pbxproj).

THEN, regardless of which path above applies, once I have the 6 config
files (3x google-services.json, 3x GoogleService-Info.plist):
- Add firebase_core, firebase_crashlytics, firebase_analytics,
  firebase_messaging, firebase_remote_config to pubspec.yaml
- Generate per-flavor firebase_options.dart files (or use flutterfire
  configure per flavor) and wire environment selection into the app's
  existing bootstrap/main.dart using whatever env-detection pattern
  already exists in this codebase — check first, don't introduce a second
  one
- Place the Android google-services.json files per flavor source set
  (android/app/src/dev/, src/stage/, src/prod/) and add the
  google-services + firebase-crashlytics Gradle plugins
- Set up per-scheme GoogleService-Info.plist selection on iOS (a build
  phase script keyed on ${CONFIGURATION} matching the existing
  Debug/Release/Profile-{dev,stage,prod} scheme names)
- Wire Crashlytics (disabled in debug builds), Analytics (plumbing only),
  Cloud Messaging (permission request + token logging, no backend wiring
  yet), and Remote Config (short fetch interval dev/stage, 1h prod)
- Ensure google-services.json / GoogleService-Info.plist are in
  .gitignore if they aren't already, since they'll contain real project
  data
- Run flutter pub get and flutter analyze to confirm everything compiles
- Give me a final file-by-file summary and a checklist of anything I
  still need to do manually

Project path: /Users/reddygona/Documents/skills/laundry_pos_mobile
```
