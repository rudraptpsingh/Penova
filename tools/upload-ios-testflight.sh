#!/usr/bin/env bash
#
#  upload-ios-testflight.sh
#  Penova
#
#  Turnkey "ship a TestFlight build" pipeline:
#    1. xcodegen → Penova.xcodeproj
#    2. xcodebuild archive (App Store / TestFlight signing)
#    3. xcodebuild -exportArchive (.ipa)
#    4. xcrun altool --upload-app to App Store Connect
#
#  After upload, App Store Connect spends ~10–20 min processing.
#  Once it lights up green in TestFlight, internal testers can run it
#  immediately; promote to public beta or App Review from the web UI.
#
#  Prerequisites:
#    1. Apple Developer Program membership active.
#    2. App ID `com.rudrapratapsingh.penova` registered with the
#       Sign in with Apple capability.
#    3. App record created in App Store Connect for that bundle ID.
#    4. App-specific password generated at https://appleid.apple.com.
#
#  Required env vars:
#    PENOVA_TEAM_ID             10-char Apple Developer team ID
#    PENOVA_APPLE_ID            Apple ID email (for altool auth)
#    PENOVA_APP_PASSWORD        App-specific password
#  Optional:
#    PENOVA_VERSION             Override MARKETING_VERSION
#    PENOVA_BUILD_NUMBER        Override CURRENT_PROJECT_VERSION
#                               (must be unique per upload — bump every time)

set -euo pipefail

TEAM_ID="${PENOVA_TEAM_ID:?Set PENOVA_TEAM_ID to your 10-char Apple Developer team ID}"
APPLE_ID="${PENOVA_APPLE_ID:?Set PENOVA_APPLE_ID to your Apple ID email}"
APP_PASSWORD="${PENOVA_APP_PASSWORD:?Set PENOVA_APP_PASSWORD to an app-specific password}"
SCHEME="Penova"
PROJECT="Penova.xcodeproj"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME-iOS.xcarchive"
EXPORT_DIR="$BUILD_DIR/release-ios"
IPA_PATH="$EXPORT_DIR/Penova.ipa"
EXPORT_OPTIONS_TEMPLATE="tools/iOSExportOptions.plist.template"
EXPORT_OPTIONS_BUILT="$BUILD_DIR/iOSExportOptions.plist"

RED=$(printf '\033[0;31m'); GREEN=$(printf '\033[0;32m'); BLUE=$(printf '\033[0;34m'); RESET=$(printf '\033[0m')
say() { printf "%s→%s %s\n" "$BLUE" "$RESET" "$1"; }
ok()  { printf "%s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
die() { printf "%s✗%s %s\n" "$RED" "$RESET" "$1" >&2; exit 1; }

command -v xcodegen   >/dev/null 2>&1 || die "xcodegen not installed (brew install xcodegen)"
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not on PATH (Xcode + command-line tools)"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$EXPORT_OPTIONS_BUILT"

[[ -f "$EXPORT_OPTIONS_TEMPLATE" ]] || die "Missing $EXPORT_OPTIONS_TEMPLATE"
sed "s/{{TEAM_ID}}/$TEAM_ID/g" "$EXPORT_OPTIONS_TEMPLATE" > "$EXPORT_OPTIONS_BUILT"
ok "Wrote $EXPORT_OPTIONS_BUILT"

say "Regenerating $PROJECT"
xcodegen 2>&1 | tail -3

say "Archiving $SCHEME for iOS device (release config)"
ARCHIVE_FLAGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination 'generic/platform=iOS'
  -archivePath "$ARCHIVE_PATH"
  -configuration Release
  DEVELOPMENT_TEAM="$TEAM_ID"
  CODE_SIGN_STYLE=Automatic
  -allowProvisioningUpdates
)
[[ -n "${PENOVA_VERSION:-}" ]]      && ARCHIVE_FLAGS+=("MARKETING_VERSION=$PENOVA_VERSION")
[[ -n "${PENOVA_BUILD_NUMBER:-}" ]] && ARCHIVE_FLAGS+=("CURRENT_PROJECT_VERSION=$PENOVA_BUILD_NUMBER")

xcodebuild archive "${ARCHIVE_FLAGS[@]}" -quiet
ok "Archive at $ARCHIVE_PATH"

say "Exporting App Store-signed .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_BUILT" \
  -allowProvisioningUpdates \
  -quiet

[[ -f "$IPA_PATH" ]] || die "Expected $IPA_PATH after export"
ok "Exported $IPA_PATH"

say "Uploading to App Store Connect (this can take 5–15 min)"
xcrun altool --upload-app \
  -f "$IPA_PATH" \
  -t ios \
  -u "$APPLE_ID" \
  -p "$APP_PASSWORD" \
  --output-format xml

cat <<EOM

$(printf '\033[0;32m')Done.$(printf '\033[0m')

  artifact:   $IPA_PATH

Next steps:
  • Wait ~10–20 min for App Store Connect to process the build.
  • Visit https://appstoreconnect.apple.com → Penova → TestFlight.
  • Once green, add testers (internal users see it immediately,
    external testers go through a one-time Beta App Review).
  • Bump PENOVA_BUILD_NUMBER for the next upload — App Store
    Connect rejects duplicates.

EOM
