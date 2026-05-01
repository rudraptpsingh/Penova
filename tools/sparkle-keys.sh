#!/usr/bin/env bash
#
#  sparkle-keys.sh
#  Penova
#
#  ONE-TIME setup script. Generates the Sparkle EdDSA signing key
#  pair and prints the public key in a format you can paste into
#  Info.plist's `SUPublicEDKey` value (see PenovaMac/App/Info.plist).
#
#  How Sparkle's update verification works:
#    • Private key — stays on this Mac (in your login keychain).
#    • Public key — embedded in the shipped app's Info.plist so the
#      installed app can verify any update DMG it downloads.
#    • Each release artifact (DMG) is signed by tools/sign-update.sh
#      with the private key. The 88-char EdDSA signature lands in
#      the appcast.xml entry's `sparkle:edSignature` attribute.
#
#  Run this once and paste the printed public key into Info.plist.
#  After that, never re-run — your shipped users' apps would stop
#  trusting future updates.
#
#  Prereq: Sparkle's `generate_keys` binary, which ships in the
#          Sparkle SPM package after first build. The script
#          locates it under DerivedData.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GENERATE_KEYS=$(find ~/Library/Developer/Xcode/DerivedData \
  -type f -name "generate_keys" -path "*/Sparkle*/bin/generate_keys" 2>/dev/null \
  | head -1 || true)

if [[ -z "$GENERATE_KEYS" ]]; then
  echo "✗ Sparkle's generate_keys not found." >&2
  echo "  Build PenovaMac at least once (xcodebuild build -scheme PenovaMac)" >&2
  echo "  so the Sparkle SPM package's bin/ tools resolve, then re-run." >&2
  exit 1
fi

echo "→ Generating Sparkle EdDSA key pair (stored in your login keychain)…"
"$GENERATE_KEYS"

echo
echo "✅ Done. Paste the PUBLIC key above into:"
echo "     PenovaMac/App/Info.plist  →  <key>SUPublicEDKey</key>"
echo
echo "   The PRIVATE key now lives in your login keychain under the name"
echo "   'ed25519' (per Sparkle convention) and will be used by"
echo "   tools/sign-update.sh to sign every release."
