# Real-script PDF fixtures

This directory holds real-world screenplay PDFs/FDX/Fountain files used
to test `PDFScreenplayParser` and `FDXReader`. Files are **gitignored**
— the screenplay copyrights belong to the writers, not to us.

## Quick start

```sh
./tools/fetch_reference_scripts.sh        # populates this directory
python3 tools/verify_parser.py            # cross-platform parser audit
```

The fetch script downloads three canonical Fountain reference
screenplays from `vilcans/screenplain` (BSD-licensed source tree, with
the screenplays themselves attributable to John August / Stu Maschwitz):

| File | Author | Pages | Use it for |
|---|---|---|---|
| `Big-Fish.pdf` | John August (2003 Tim Burton film) | 122 | Feature-length stress test, non-WGA dialogue indent (174pt), 192 scenes |
| `Brick-and-Steel.pdf` | Stu Maschwitz | 4 | Clean WGA layout, all element kinds, transitions |
| `The-Last-Birthday-Card.pdf` | Stu Maschwitz | ~10 | Multi-page with substantial dialogue, multiple title-page contact lines |

The corresponding `.fdx` files are also fetched so `FDXReader` gets the
same coverage.

## Adding more fixtures

Drop any `.pdf`, `.fdx`, or `.fountain` into this directory:

```sh
cp ~/Downloads/some-other-script.pdf PenovaTests/Fixtures/screenplays/
```

The Swift test `PDFRoundTripImportTests.realFixturesParseCleanly` (and
its FDX counterpart) auto-discovers them. The cross-platform verifier
also accepts targeted file paths:

```sh
python3 tools/verify_parser.py PenovaTests/Fixtures/screenplays/some-other-script.pdf
```

## Invariants the test suite asserts

For every PDF found in this directory:

- ≥ 1 scene parsed (at least one `INT.` / `EXT.` / `EST.` heading)
- ≥ 1 character cue across all scenes (dialogue is being recognised)

These are intentionally permissive — a well-formed screenplay PDF, no
matter the studio template, should clear them. If a real script trips
this baseline, that's a high-value bug to file (and likely the same
bug other users with similar templates would hit on import).

## On copyrighted scripts

Studio "For Your Consideration" PDFs and the scripts on dailyscript /
imsdb / archive.org are copyrighted. They're posted under implicit
limited-circulation permission, not under any redistribution licence.
**Don't commit them here**. The `.gitignore` blocks it by default, but
double-check before `git add -A`.

The three reference scripts the fetch script pulls are the well-known
exception — John August and Stu Maschwitz explicitly released their
work as Fountain references for tooling like ours, and they're widely
redistributed in screenplay-tooling test suites for that reason.
