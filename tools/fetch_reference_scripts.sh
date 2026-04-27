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

echo "→ extracting reference screenplays…"
tar -xzf "$WORK/sp.tgz" -C "$WORK" \
  screenplain-master/examples/Big-Fish.pdf \
  screenplain-master/examples/Big-Fish.fdx \
  screenplain-master/examples/Brick-and-Steel.pdf \
  screenplain-master/examples/Brick-and-Steel.fdx \
  screenplain-master/examples/The-Last-Birthday-Card.pdf \
  screenplain-master/examples/The-Last-Birthday-Card.fdx

cp "$WORK/screenplain-master/examples/"*.pdf "$DEST/"
cp "$WORK/screenplain-master/examples/"*.fdx "$DEST/"

echo "✓ Wrote:"
ls -1 "$DEST"/*.pdf "$DEST"/*.fdx 2>/dev/null | sed 's|^|  |'

echo
echo "These files are .gitignored — they will not be committed."
echo "Run python3 tools/verify_parser.py to validate, or run the Xcode"
echo "test suite to exercise PDFRoundTripImportTests.realFixturesParseCleanly."
