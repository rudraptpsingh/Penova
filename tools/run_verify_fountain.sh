#!/usr/bin/env bash
# run_verify_fountain.sh — compile tools/verify_fountain.swift against
# the in-tree FountainParser and run it over every .fountain file under
# PenovaTests/Fixtures/screenplays/. No iOS simulator needed; pure
# host-side Swift compile.
#
# Usage:
#   ./tools/run_verify_fountain.sh                  # all fountain fixtures
#   ./tools/run_verify_fountain.sh some.fountain    # one file
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d)"
trap "rm -rf '$WORK'" EXIT

# Strip `import SwiftData` and the FountainImporter section (which uses
# SwiftData types like Project / ModelContext that we don't need to test
# the parser itself).
sed -e 's/^import SwiftData//' Penova/Features/Import/FountainParser.swift \
    | awk '/^\/\/ MARK: - SwiftData importer/{stop=1} !stop' \
    > "$WORK/fp.swift"

# Pull only the enums FountainParser depends on from the model file —
# avoids dragging in Project / SwiftData-decorated types.
sed -n '/^public enum SceneLocation/,/^}/p;/^public enum SceneTimeOfDay/,/^}/p;/^public enum SceneElementKind/,/^}/p' \
    PenovaSpec/Models.swift > "$WORK/models.swift"

# Driver expects to be named main.swift when compiled with auxiliary files.
cp tools/verify_fountain.swift "$WORK/main.swift"

swiftc -O -o "$WORK/verify_fountain" \
    "$WORK/main.swift" "$WORK/fp.swift" "$WORK/models.swift"

if [[ $# -gt 0 ]]; then
    "$WORK/verify_fountain" "$@"
else
    shopt -s nullglob
    files=( PenovaTests/Fixtures/screenplays/*.fountain \
            PenovaTests/Fixtures/screenplays/fountain-edge-cases/*.fountain )
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No .fountain fixtures found. Run tools/fetch_reference_scripts.sh first." >&2
        exit 2
    fi
    "$WORK/verify_fountain" "${files[@]}"
fi
