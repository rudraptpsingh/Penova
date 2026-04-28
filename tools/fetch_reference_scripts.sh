#!/usr/bin/env bash
# fetch_reference_scripts.sh — download the canonical Fountain reference
# screenplays into the test fixtures directory.
#
# These are real, widely-used industry-format PDFs:
#   - Brick & Steel, Full Retired   — Stu Maschwitz
#   - The Last Birthday Card        — Stu Maschwitz
#   - Big Fish                      — John August (2003 Tim Burton film)
#
# All three ship in `screenplain` (https://github.com/vilcans/screenplain),
# whose top-level licence is MIT. The screenplays themselves remain
# under their authors' copyright — we use them locally for parser
# testing only and the fixtures directory is .gitignored so they never
# enter the Penova repo.
#
# Run from the repo root:
#     ./tools/fetch_reference_scripts.sh
#
# Then re-run the test suite (PDFRoundTripImportTests.realFixturesParseCleanly
# auto-discovers anything in PenovaTests/Fixtures/screenplays/) or the
# cross-platform verifier:
#     python3 tools/verify_parser.py

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/PenovaTests/Fixtures/screenplays"
mkdir -p "$DEST"

WORK="$(mktemp -d)"
trap "rm -rf '$WORK'" EXIT

echo "→ downloading screenplain (BSD-licensed) source tree…"
curl -fsSL --max-time 60 \
  "https://codeload.github.com/vilcans/screenplain/tar.gz/master" \
  -o "$WORK/sp.tgz"

echo "→ extracting reference screenplays + fountain edge cases…"
tar -xzf "$WORK/sp.tgz" -C "$WORK" \
  screenplain-master/examples/Big-Fish.pdf \
  screenplain-master/examples/Big-Fish.fdx \
  screenplain-master/examples/Big-Fish.fountain \
  screenplain-master/examples/Brick-and-Steel.pdf \
  screenplain-master/examples/Brick-and-Steel.fdx \
  screenplain-master/examples/Brick-and-Steel.fountain \
  screenplain-master/examples/The-Last-Birthday-Card.pdf \
  screenplain-master/examples/The-Last-Birthday-Card.fdx \
  screenplain-master/examples/The-Last-Birthday-Card.fountain \
  screenplain-master/tests/files/dialogue.fountain \
  screenplain-master/tests/files/dual-dialogue.fountain \
  screenplain-master/tests/files/forced-action.fountain \
  screenplain-master/tests/files/forced-transition.fountain \
  screenplain-master/tests/files/indentation.fountain \
  screenplain-master/tests/files/notes.fountain \
  screenplain-master/tests/files/page-break.fountain \
  screenplain-master/tests/files/parenthetical.fountain \
  screenplain-master/tests/files/scene-numbers.fountain \
  screenplain-master/tests/files/sections.fountain \
  screenplain-master/tests/files/title-page.fountain \
  screenplain-master/tests/files/utf-8-bom.fountain

cp "$WORK/screenplain-master/examples/"*.pdf "$DEST/"
cp "$WORK/screenplain-master/examples/"*.fdx "$DEST/"
cp "$WORK/screenplain-master/examples/"*.fountain "$DEST/"
mkdir -p "$DEST/fountain-edge-cases"
cp "$WORK/screenplain-master/tests/files/"*.fountain "$DEST/fountain-edge-cases/"

echo "✓ Wrote:"
ls -1 "$DEST"/*.pdf "$DEST"/*.fdx "$DEST"/*.fountain 2>/dev/null | sed 's|^|  |'
ls -1 "$DEST"/fountain-edge-cases/*.fountain 2>/dev/null | sed 's|^|  edge-case: |'

echo
echo "These files are .gitignored — they will not be committed."
echo
echo "Validate with the Swift test suite:"
echo "  xcodebuild test -scheme Penova -destination 'platform=iOS Simulator,name=iPhone 17'"
echo
echo "Or with host-side cross-checks (no simulator needed):"
echo "  python3 tools/verify_with_pdfplumber.py            # PDF + FDX"
echo "  bash tools/run_verify_fountain.sh                  # Fountain via Swift CLI"
