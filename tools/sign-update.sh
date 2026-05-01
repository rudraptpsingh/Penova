#!/usr/bin/env bash
#
#  sign-update.sh
#  Penova
#
#  Signs a release DMG with the Sparkle EdDSA private key (stored in
#  your login keychain by `sparkle-keys.sh`) and prints a ready-to-
#  paste appcast.xml `<item>` block. Run this after notarize-mac.sh
#  succeeds; pipe the output into your appcast.xml file.
#
#  Usage:
#    tools/sign-update.sh build/Penova.dmg \
#      --version 1.0.1 \
#      --build 42 \
#      --notes-url https://penova.app/release-notes/1.0.1.html
#
#  Required:
#    $1            Path to the notarized DMG (from notarize-mac.sh)
#    --version     Marketing version, e.g. "1.0.1"
#  Optional:
#    --build       CFBundleVersion (default: same as --version)
#    --notes-url   URL with HTML release notes Sparkle will show
#                  in the update dialog
#    --min-os      Minimum macOS version (default: 14.0)

set -euo pipefail

DMG=""
VERSION=""
BUILD=""
NOTES_URL=""
MIN_OS="14.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   VERSION="$2"; shift 2 ;;
    --build)     BUILD="$2"; shift 2 ;;
    --notes-url) NOTES_URL="$2"; shift 2 ;;
    --min-os)    MIN_OS="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^#//'; exit 0 ;;
    *)
      [[ -z "$DMG" ]] && DMG="$1" || { echo "Unknown arg: $1" >&2; exit 1; }
      shift ;;
  esac
done

[[ -n "$DMG" && -f "$DMG" ]] || { echo "✗ Pass the DMG path as the first arg." >&2; exit 1; }
[[ -n "$VERSION" ]]          || { echo "✗ --version is required (e.g. --version 1.0.1)." >&2; exit 1; }
[[ -n "$BUILD" ]]            || BUILD="$VERSION"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData \
  -type f -name "sign_update" -path "*/Sparkle*/bin/sign_update" 2>/dev/null \
  | head -1 || true)

if [[ -z "$SIGN_UPDATE" ]]; then
  echo "✗ Sparkle's sign_update binary not found." >&2
  echo "  Build PenovaMac at least once so the Sparkle SPM tools resolve," >&2
  echo "  then re-run." >&2
  exit 1
fi

# sign_update emits ` length=...` `sparkle:edSignature="..."` to stdout.
SIG_LINE=$("$SIGN_UPDATE" "$DMG")
DMG_NAME=$(basename "$DMG")
DMG_LENGTH=$(stat -f '%z' "$DMG")
DMG_URL_DEFAULT="https://penova.app/releases/$DMG_NAME"
PUB_DATE=$(LC_ALL=en_US.UTF-8 date "+%a, %d %b %Y %H:%M:%S %z")
NOTES_LINE=""
[[ -n "$NOTES_URL" ]] && NOTES_LINE="            <sparkle:releaseNotesLink>$NOTES_URL</sparkle:releaseNotesLink>"

cat <<EOM

—— Append this <item> block to public/appcast.xml ——

        <item>
            <title>Penova $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
$NOTES_LINE
            <enclosure
                url="$DMG_URL_DEFAULT"
                type="application/x-apple-diskimage"
                length="$DMG_LENGTH"
                $SIG_LINE
            />
        </item>

—— Replace the URL above if your CDN path differs ——

EOM
