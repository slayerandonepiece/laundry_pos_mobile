#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PLATFORM=""
ENVIRONMENT=""
SKIP_TESTS=false
DRY_RUN=false
ASSUME_YES=false
CONFIRM_PROD=false
START_EPOCH="$(date +%s)"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
quote_command() { printf '%q ' "$@"; printf '\n'; }
run() {
  if $DRY_RUN; then
    printf 'DRY RUN: '
    quote_command "$@"
  else
    "$@"
  fi
}
confirm() {
  local prompt="$1" answer
  if $ASSUME_YES; then return 0; fi
  read -r -p "$prompt (y/N) " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
usage() {
  say 'Usage: scripts/release.sh [--platform android|ios|both] [--env stage|prod] [--skip-tests] [--dry-run] [--yes] [--confirm-prod]'
}

while (($#)); do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --env) ENVIRONMENT="${2:-}"; shift 2 ;;
    --skip-tests) SKIP_TESTS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --confirm-prod) CONFIRM_PROD=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

if [[ -z "$PLATFORM" ]]; then
  say 'Select platform: 1) Android 2) iOS 3) Both'
  read -r -p 'Choice: ' choice
  case "$choice" in 1) PLATFORM=android ;; 2) PLATFORM=ios ;; 3) PLATFORM=both ;; *) fail 'Invalid platform selection' ;; esac
fi
[[ "$PLATFORM" =~ ^(android|ios|both)$ ]] || fail 'Platform must be android, ios, or both'

if [[ -z "$ENVIRONMENT" ]]; then
  read -r -p 'Environment (stage/prod): ' ENVIRONMENT
fi
[[ "$ENVIRONMENT" =~ ^(stage|prod)$ ]] || fail 'Environment must be stage or prod'
if [[ "$ENVIRONMENT" == prod && "$CONFIRM_PROD" != true ]]; then
  # --yes alone never confirms a production release.
  $ASSUME_YES && fail 'Production needs --confirm-prod when --yes is used'
  read -r -p 'Type prod to confirm a production release: ' prod_confirmation
  [[ "$prod_confirmation" == prod ]] || fail 'Production release not confirmed'
fi

for tool in flutter dart firebase xcodebuild java python3; do
  command -v "$tool" >/dev/null || fail "Required tool not found: $tool"
done

[[ -f pubspec.yaml && -d lib && -d android && -d ios ]] || fail 'Run this script from the KlenPOS repository'
[[ -f "ios/Firebase/$ENVIRONMENT/GoogleService-Info.plist" ]] || fail "Missing ios/Firebase/$ENVIRONMENT/GoogleService-Info.plist"
[[ -f "android/app/src/$ENVIRONMENT/google-services.json" ]] || fail "Missing android/app/src/$ENVIRONMENT/google-services.json"
if [[ "$PLATFORM" == android || "$PLATFORM" == both ]]; then
  [[ -f android/key.properties ]] || fail 'Missing android/key.properties'
fi

BRANCH="$(git branch --show-current)"
say "Branch: ${BRANCH:-detached HEAD}"
if [[ -n "$(git status --porcelain)" ]]; then
  say 'WARNING: the working tree has uncommitted changes.'
  confirm 'Continue with the dirty working tree?' || fail 'Cancelled'
fi

VERSION_LINE="$(awk '/^version: / {print $2; exit}' pubspec.yaml)"
[[ "$VERSION_LINE" =~ ^([^+]+)\+([0-9]+)$ ]] || fail 'pubspec.yaml version must use name+build format'
VERSION_NAME="${BASH_REMATCH[1]}"
BUILD_NUMBER="${BASH_REMATCH[2]}"
say "Version: $VERSION_NAME ($BUILD_NUMBER)"

if ! $ASSUME_YES; then
  read -r -p "Has build number $BUILD_NUMBER already been uploaded? (y/N) " uploaded
  if [[ "$uploaded" =~ ^[Yy]$ ]]; then
    next_build=$((BUILD_NUMBER + 1))
    confirm "Bump only the build number to $next_build?" || fail 'Build-number bump cancelled'
    if $DRY_RUN; then
      say "DRY RUN: update pubspec.yaml version to $VERSION_NAME+$next_build"
    else
      python3 - "$VERSION_NAME" "$BUILD_NUMBER" "$next_build" <<'PY'
from pathlib import Path
import sys

path = Path('pubspec.yaml')
old = f'version: {sys.argv[1]}+{sys.argv[2]}'
new = f'version: {sys.argv[1]}+{sys.argv[3]}'
text = path.read_text()
if text.count(old) != 1:
    raise SystemExit('ERROR: version line changed before build-number bump')
path.write_text(text.replace(old, new))
PY
    fi
    BUILD_NUMBER="$next_build"
    VERSION_LINE="$VERSION_NAME+$BUILD_NUMBER"
  fi
fi

if $DRY_RUN; then
  say 'DRY RUN: firebase projects:list --json (verify Firebase login)'
else
  firebase projects:list --json >/dev/null || fail 'Firebase CLI is not logged in or cannot list projects'
fi

SYMBOL_ROOT="$HOME/klenpos-symbols/$ENVIRONMENT/$VERSION_LINE"
ANDROID_SYMBOLS="$SYMBOL_ROOT/android"
IOS_SYMBOLS="$SYMBOL_ROOT/ios"
run mkdir -p "$ANDROID_SYMBOLS" "$IOS_SYMBOLS"

run flutter clean
run flutter pub get
run dart format .
run flutter analyze
if $SKIP_TESTS; then
  say 'Tests: skipped by --skip-tests'
else
  run flutter test
fi

ANDROID_RESULT='not requested'
IOS_RESULT='not requested'

if [[ "$PLATFORM" == android || "$PLATFORM" == both ]]; then
  run flutter build appbundle --flavor "$ENVIRONMENT" -t lib/main.dart \
    "--dart-define=ENV=$ENVIRONMENT" --obfuscate \
    "--split-debug-info=$ANDROID_SYMBOLS"
  AAB="build/app/outputs/bundle/${ENVIRONMENT}Release/app-${ENVIRONMENT}-release.aab"
  JSON_PATH="android/app/src/$ENVIRONMENT/google-services.json"
  EXPECTED_PACKAGE=com.reddygona.klenpos
  [[ "$ENVIRONMENT" == stage ]] && EXPECTED_PACKAGE=com.reddygona.klenpos.staging
  if $DRY_RUN; then
    say "DRY RUN: read mobilesdk_app_id from $JSON_PATH for package $EXPECTED_PACKAGE using python3"
    say "DRY RUN: firebase crashlytics:symbols:upload --app=<id from JSON> $ANDROID_SYMBOLS"
  else
    ANDROID_APP_ID="$(python3 - "$JSON_PATH" "$EXPECTED_PACKAGE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
matches = [c.get('client_info', {}).get('mobilesdk_app_id') for c in data.get('client', [])
           if c.get('client_info', {}).get('android_client_info', {}).get('package_name') == sys.argv[2]]
if len(matches) != 1 or not matches[0]:
    raise SystemExit(f'expected exactly one Firebase client for {sys.argv[2]}')
print(matches[0])
PY
)"
    [[ -f "$AAB" ]] || fail "Android bundle not found: $AAB"
    firebase crashlytics:symbols:upload --app="$ANDROID_APP_ID" "$ANDROID_SYMBOLS"
    open -R "$AAB"
  fi
  ANDROID_RESULT="bundle $AAB; symbols $ANDROID_SYMBOLS"
fi

if [[ "$PLATFORM" == ios || "$PLATFORM" == both ]]; then
  run flutter build ios --release --config-only --flavor "$ENVIRONMENT" \
    "--dart-define=ENV=$ENVIRONMENT" --obfuscate \
    "--split-debug-info=$IOS_SYMBOLS"
  say 'Xcode archive steps:'
  say "  1. Select scheme $ENVIRONMENT."
  say '  2. Select destination Any iOS Device (arm64).'
  say '  3. Choose Product > Archive.'
  say '  4. When it finishes, Xcode opens Organizer: click Distribute App.'
  say '     This script waits for the archive and checks it; nothing to press here.'
  run open ios/Runner.xcworkspace
  if $DRY_RUN; then
    say 'DRY RUN: wait for a new Xcode archive to appear (up to 60 minutes)'
    say 'DRY RUN: find newest archive, verify start time, bundle id, version, and build'
    say 'DRY RUN: dSYMs are uploaded by the Xcode build phase during the archive'
    say 'DRY RUN: Xcode opens Organizer itself; the script does not reopen the archive'
    IOS_RESULT="Xcode archive pending; Dart symbols $IOS_SYMBOLS"
  else
    say 'Waiting for the Xcode archive to finish (Ctrl-C to cancel)...'
    ARCHIVE=''
    for _ in $(seq 720); do
      ARCHIVE="$(python3 - "$HOME/Library/Developer/Xcode/Archives" "$START_EPOCH" <<'PY'
from pathlib import Path
import sys
items = [p for p in Path(sys.argv[1]).glob('*/*.xcarchive')
         if p.stat().st_mtime >= int(sys.argv[2])]
if items:
    print(max(items, key=lambda path: path.stat().st_mtime))
PY
)"
      [[ -n "$ARCHIVE" ]] && break
      sleep 5
    done
    [[ -n "$ARCHIVE" ]] || fail 'No new Xcode archive appeared within 60 minutes'
    sleep 5 # let Xcode finish writing the archive
    ARCHIVE_EPOCH="$(stat -f %m "$ARCHIVE")"
    (( ARCHIVE_EPOCH >= START_EPOCH )) || fail 'Newest archive is older than this script run'
    INFO_PLIST="$ARCHIVE/Products/Applications/Runner.app/Info.plist"
    [[ -f "$INFO_PLIST" ]] || fail "Archive app Info.plist not found: $INFO_PLIST"
    EXPECTED_BUNDLE=com.reddygona.klenpos
    [[ "$ENVIRONMENT" == stage ]] && EXPECTED_BUNDLE=com.reddygona.klenpos.staging
    ACTUAL_BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
    ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
    ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
    [[ "$ACTUAL_BUNDLE" == "$EXPECTED_BUNDLE" ]] || fail "Archive bundle id mismatch: expected $EXPECTED_BUNDLE"
    [[ "$ACTUAL_VERSION" == "$VERSION_NAME" ]] || fail "Archive version mismatch: expected $VERSION_NAME"
    [[ "$ACTUAL_BUILD" == "$BUILD_NUMBER" ]] || fail "Archive build mismatch: expected $BUILD_NUMBER"
    # dSYMs are uploaded by the "[firebase_crashlytics] Upload Symbols" build phase during the archive.
    # Xcode opens Organizer by itself after archiving, so the archive is not reopened here.
    IOS_RESULT="archive $ARCHIVE; Dart symbols $IOS_SYMBOLS; dSYMs uploaded by the Xcode build phase"
  fi
fi

say 'Release preparation summary'
say "  Environment: $ENVIRONMENT"
say "  Version: $VERSION_NAME ($BUILD_NUMBER)"
say "  Android: $ANDROID_RESULT"
say "  iOS: $IOS_RESULT"
say '  Store upload: NOT performed; validation and distribution remain manual.'
if $DRY_RUN; then say 'DRY RUN COMPLETE'; fi
