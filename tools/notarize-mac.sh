#!/usr/bin/env bash
#
#  notarize-mac.sh
#  Penova
#
#  Turnkey "ship a downloadable Mac DMG" pipeline:
#    1. xcodegen → Penova.xcodeproj
#    2. xcodebuild archive (Developer ID Application signed)
#    3. xcodebuild -exportArchive (.app bundle)
#    4. notarize the .app
#    5. staple the notarization ticket to .app
#    6. wrap into a UDZO DMG
#    7. notarize the DMG
#    8. staple the notarization ticket to DMG
#
#  Output: build/Penova.dmg — ready to upload to your website.
#  Users who download it can right-click → Open and Gatekeeper will
#  honour the stapled ticket; no "unidentified developer" warning.
#
#  Prerequisites (run once on this Mac):
#    1. Apple Developer Program membership active.
#    2. Developer ID Application certificate installed in login keychain
#       (Xcode → Settings → Accounts → Manage Certificates → +).
#    3. App-specific password generated at https://appleid.apple.com.
#    4. Hand notarytool credentials. Two paths supported, in order:
#       a) Keychain profile (cleanest for repeat use on one machine):
#            xcrun notarytool store-credentials penova-notary \
#              --apple-id "you@example.com" \
#              --team-id  "ABCDE12345" \
#              --password "abcd-efgh-ijkl-mnop"
#          Then export PENOVA_NOTARY_PROFILE=penova-notary.
#       b) Inline env vars (matches the slipstream / GitHub Actions
#          pattern — same secret names work as-is):
#            export APPLE_ID=you@example.com
#            export APPLE_TEAM_ID=ABCDE12345
#            export APPLE_APP_SPECIFIC_PASSWORD=abcd-efgh-ijkl-mnop
#
#  Required env vars at run time:
#    PENOVA_TEAM_ID                Apple Developer 10-char team ID
#                                  (or APPLE_TEAM_ID — same thing)
#  At least one of:
#    PENOVA_NOTARY_PROFILE         Keychain profile name
#    APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD (+ APPLE_TEAM_ID)
#  Optional:
#    PENOVA_VERSION                Override MARKETING_VERSION (e.g. 1.0.1)
#    PENOVA_BUILD_NUMBER           Override CURRENT_PROJECT_VERSION

set -euo pipefail

# -------- Config ------------------------------------------------------

# Team ID resolution: prefer Penova-specific, fall back to the
# slipstream-style APPLE_TEAM_ID so existing operators don't have
# to set anything new.
TEAM_ID="${PENOVA_TEAM_ID:-${APPLE_TEAM_ID:-}}"
[[ -n "$TEAM_ID" ]] || {
  echo "✗ Set PENOVA_TEAM_ID (or APPLE_TEAM_ID) to your 10-char Apple Developer team ID." >&2
  exit 1
}

# Notarytool auth resolution. If a keychain profile is set we use it;
# otherwise we fall back to the inline env-var triple.
NOTARY_PROFILE="${PENOVA_NOTARY_PROFILE:-}"
APPLE_ID_VALUE="${APPLE_ID:-}"
APPLE_PASSWORD_VALUE="${APPLE_APP_SPECIFIC_PASSWORD:-${APPLE_PASSWORD:-}}"

# Choose auth mode.
if [[ -n "$NOTARY_PROFILE" ]]; then
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "$APPLE_ID_VALUE" && -n "$APPLE_PASSWORD_VALUE" ]]; then
  NOTARY_AUTH=(
    --apple-id "$APPLE_ID_VALUE"
    --password "$APPLE_PASSWORD_VALUE"
    --team-id  "$TEAM_ID"
  )
else
  echo "✗ Neither PENOVA_NOTARY_PROFILE nor APPLE_ID/APPLE_APP_SPECIFIC_PASSWORD is set." >&2
  echo "  Set up one of the two auth paths described in the script header." >&2
  exit 1
fi

SCHEME="PenovaMac"
APP_NAME="Penova"
PROJECT="Penova.xcodeproj"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/release-mac"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME-app.zip"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
EXPORT_OPTIONS_TEMPLATE="tools/MacExportOptions.plist.template"
EXPORT_OPTIONS_BUILT="$BUILD_DIR/MacExportOptions.plist"

# Colors for the script's own output (not piped to xcodebuild).
RED=$(printf '\033[0;31m'); GREEN=$(printf '\033[0;32m'); BLUE=$(printf '\033[0;34m'); RESET=$(printf '\033[0m')
say() { printf "%s→%s %s\n" "$BLUE" "$RESET" "$1"; }
ok()  { printf "%s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
die() { printf "%s✗%s %s\n" "$RED" "$RESET" "$1" >&2; exit 1; }

# -------- Sanity ------------------------------------------------------

command -v xcodegen   >/dev/null 2>&1 || die "xcodegen not installed (brew install xcodegen)"
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not on PATH (Xcode + command-line tools)"
command -v hdiutil    >/dev/null 2>&1 || die "hdiutil missing (should be on every Mac)"
command -v ditto      >/dev/null 2>&1 || die "ditto missing (should be on every Mac)"

# -------- Reset build dir --------------------------------------------

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$ZIP_PATH" "$DMG_PATH" "$EXPORT_OPTIONS_BUILT"

# -------- Substitute team ID in ExportOptions ------------------------

[[ -f "$EXPORT_OPTIONS_TEMPLATE" ]] || die "Missing $EXPORT_OPTIONS_TEMPLATE"
sed "s/{{TEAM_ID}}/$TEAM_ID/g" "$EXPORT_OPTIONS_TEMPLATE" > "$EXPORT_OPTIONS_BUILT"
ok "Wrote $EXPORT_OPTIONS_BUILT"

# -------- Regenerate Xcode project -----------------------------------

say "Regenerating $PROJECT"
xcodegen 2>&1 | tail -3

# -------- Archive ----------------------------------------------------

say "Archiving $SCHEME (Developer ID, hardened runtime, sandbox)"
ARCHIVE_FLAGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination 'generic/platform=macOS'
  -archivePath "$ARCHIVE_PATH"
  -configuration Release
  DEVELOPMENT_TEAM="$TEAM_ID"
  CODE_SIGN_STYLE=Automatic
  -allowProvisioningUpdates
)
[[ -n "${PENOVA_VERSION:-}" ]]      && ARCHIVE_FLAGS+=("MARKETING_VERSION=$PENOVA_VERSION")
[[ -n "${PENOVA_BUILD_NUMBER:-}" ]] && ARCHIVE_FLAGS+=("CURRENT_PROJECT_VERSION=$PENOVA_BUILD_NUMBER")

xcodebuild archive "${ARCHIVE_FLAGS[@]}" | xcbeautify --quieter 2>/dev/null \
  || xcodebuild archive "${ARCHIVE_FLAGS[@]}" -quiet
ok "Archive at $ARCHIVE_PATH"

# -------- Export Developer-ID-signed .app ----------------------------

say "Exporting .app with Developer ID Application certificate"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_BUILT" \
  -allowProvisioningUpdates \
  -quiet

[[ -d "$APP_PATH" ]] || die "Expected $APP_PATH after export"
ok "Exported to $APP_PATH"

# -------- Notarize the .app ------------------------------------------

say "Zipping .app for notarytool submission"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

say "Submitting .app to Apple notary service (this can take 1–5 min)"
xcrun notarytool submit "$ZIP_PATH" "${NOTARY_AUTH[@]}" --wait
ok ".app notarized"

# -------- Staple the .app --------------------------------------------

say "Stapling .app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH" >/dev/null
ok ".app stapled (Gatekeeper will honour the ticket offline)"

# -------- Build DMG --------------------------------------------------

say "Building DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null
ok "DMG at $DMG_PATH"

# -------- Notarize the DMG -------------------------------------------

say "Submitting DMG to notary service"
xcrun notarytool submit "$DMG_PATH" "${NOTARY_AUTH[@]}" --wait
ok "DMG notarized"

# -------- Staple the DMG ---------------------------------------------

say "Stapling DMG"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH" >/dev/null

# -------- Done -------------------------------------------------------

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
DMG_SHA=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist")

cat <<EOM

$(printf '\033[0;32m')Done.$(printf '\033[0m')

  artifact:   $DMG_PATH
  size:       $DMG_SIZE
  version:    $APP_VERSION ($APP_BUILD)
  sha256:     $DMG_SHA

Next steps:
  • Upload $DMG_PATH to your distribution server.
  • Update the website's download link + sha256 checksum on the page.
  • Tag the release in git:
      git tag -a v$APP_VERSION -m "Release $APP_VERSION"
      git push --tags

EOM
