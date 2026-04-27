# Real-script PDF fixtures

Drop `.pdf` or `.fdx` files into this directory and the tests in
`PDFRoundTripImportTests.realFixturesParseCleanly` /
`realFDXFixturesParseCleanly` will pick them up automatically — no code
edits needed.

## Invariants every fixture must satisfy

- Parses to **≥ 1 scene** (a screenplay with no INT./EXT./EST. headings
  almost certainly isn't a screenplay).
- Parses to **≥ 1 character cue** across all scenes (otherwise our
  ALL-CAPS / column heuristics regressed).

## Recommended sources

These hosts publish screenplay PDFs intended for educational study.
Verify each script's licence before adding it; many shared scripts are
copyrighted, even when freely distributed.

- **Internet Archive** (`archive.org`) — the cleanest path to public-domain
  scripts. Search "screenplay" with rights filtered to "Public domain".
- **WGA Foundation library** — reading-room scans of historic scripts.
- **Studio "For Your Consideration" pages** — major studios occasionally
  publish award-season scripts publicly.
- **Author personal sites** — Tarantino, Sorkin, and others have hosted
  some of their own scripts directly.

## Running locally

Without dropping any PDFs the test still passes (it's a no-op when the
directory is empty). With one or more PDFs present:

```
xcodebuild -scheme Penova test \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

You can also run the cross-platform Python verifier on the same files:

```
python3 tools/verify_parser.py PenovaTests/Fixtures/screenplays/your-script.pdf
```

That uses `pdftotext -bbox-layout` to extract per-line geometry and runs
a faithful Python port of the Swift parser logic, so you can validate
the algorithm without the iOS simulator.

## Why the directory is committed empty

We don't bundle any third-party scripts in the repo — licences vary and
many "public" PDFs aren't actually freely redistributable. The tests
treat an empty fixtures directory as "no real coverage right now,
that's fine" and rely on the synthetic Final-Draft-style PDF generated
by `tools/verify_parser.py` plus the `ScriptPDFRenderer` round-trip in
`PDFRoundTripImportTests` for default coverage.
