# The Penova Fountain dialect — v1.2

> **This is a backend / on-disk serialization document. It does not
> describe anything the user types in the editor.** When a Penova user
> writes a screenplay, they see the normal three-pane editor (Tab to
> cycle element types, ⌘1–⌘7 to set them directly) — the same way
> they always have. The `Penova-` title-page keys, `[[Penova: …]]`
> element notes, and `/* Penova-Episode: … */` boneyard delimiters
> below are **only ever produced by the exporter and consumed by the
> parser**. Users would only see them if they opened the saved
> `.fountain` file in a plain-text editor — and even then, the
> standard Fountain syntax (`Title:`, scene headings, character cues)
> is what dominates; the Penova extensions are metadata sprinkled in
> places the standard already permits ignored values.

Penova stores screenplays in a SwiftData document graph today. That works
on Apple platforms. It will not work on Windows. To make Penova portable
without forcing a future Windows team to re-derive every modeling
decision, **Fountain plain-text is being promoted to the canonical
interchange format** between platforms — and, eventually, the source of
truth at rest if the user opts into "Fountain folder mode."

The choice of plain-text Fountain (rather than a proprietary binary
format) buys three things:

1. **Windows portability.** A future Windows port reads the same files
   Mac/iOS write — no separate binary format to re-implement.
2. **Git-diffability.** Writers who keep their scripts in Git see
   meaningful line-by-line diffs across revisions.
3. **Interop.** Highland, Slugline, Beat, KIT Scenarist, Final Draft
   (via FDX bridge) all read or import Fountain. A Penova user can
   hand off a script to a collaborator using a different tool with
   zero conversion friction.

This document is the contract. Anyone porting Penova to a new platform
should be able to read this and a working `.fountain` file, and produce
an identical render. Existing Penova engineers should treat any change
to this document as an API-stability event.

## Reading order

1. **The standard:** Penova's dialect is a strict superset of the
   community-maintained Fountain spec at <https://fountain.io/syntax/>.
   Everything documented there must round-trip without loss. If you
   find a case where it doesn't, that's a bug in the parser or
   exporter — not in this document.
2. **The extensions:** Penova adds five categories of metadata that
   plain Fountain doesn't natively express. Each extension uses a
   syntax that the reference Fountain spec already permits (custom
   title-page keys, boneyard comments `/* … */`, or notes
   `[[ … ]]`) so non-Penova tools (Highland, Slugline, Beat) read
   our files as valid Fountain — they just don't see the extension
   data.
3. **Round-trip guarantee:** for every supported field below, we
   commit to `parse(export(project)) == project` modulo whitespace
   normalization and ordering of equivalent siblings. Property
   tests in `PenovaTests/FountainRoundTripTests` enforce this.

## Title page keys

| Key                        | Source                       | Standard | Required |
| -------------------------- | ---------------------------- | -------- | -------- |
| `Title:`                   | `Project.titlePage.title`    | yes      | yes      |
| `Credit:`                  | `TitlePage.credit`           | yes      | no       |
| `Author:`                  | `TitlePage.author`           | yes      | no       |
| `Source:`                  | `TitlePage.source`           | yes      | no       |
| `Draft date:`              | `TitlePage.draftDate`        | yes      | no       |
| `Contact:`                 | `TitlePage.contact`          | yes      | no       |
| `Notes:`                   | `TitlePage.notes` + `Project.logline` | extension (Beat-compatible) | no |
| `Copyright:`               | `TitlePage.copyright`        | extension | no |
| `Penova-Draft-Stage:`      | `TitlePage.draftStage`       | extension | no |
| `Penova-Genre:`            | `Project.genre` (CSV)        | extension | no |
| `Penova-Status:`           | `Project.status`             | extension | no |
| `Penova-Locked:`           | `Project.locked`             | extension | no |
| `Penova-Locked-At:`        | `Project.lockedAt` (ISO 8601) | extension | no |
| `Penova-Locked-Numbers:`   | `Project.lockedSceneNumbers` (JSON) | extension | no |
| `Penova-Active-Revision:`  | `Project.activeRevision?.id` | extension | no |

**Continuation lines.** A value that wraps to multiple lines is indented
3 spaces or one tab. The exporter always uses 3 spaces. The parser
accepts either.

**Empty fields.** An empty value omits the key entirely. Round-trip
preserves this — empty values do not become `Key:\n` lines.

**Unknown keys.** The parser stores unrecognized keys in
`ParsedDocument.unknownTitleKeys: [String: String]` (see _Extensions →
Forward compatibility_) so a Penova v1.2 file opened in v1.1 doesn't
silently lose data.

## Body element syntax

Penova's body parser implements the documented Fountain spec literally,
plus the extensions in the next section. Here's the canonical mapping
between Fountain syntax and Penova's `SceneElementKind`:

| `SceneElementKind` | Fountain canonical form | Notes |
| ------------------ | ----------------------- | ----- |
| `.heading`         | `INT.`/`EXT.`/`EST.`/`INT./EXT.` line at start of paragraph; or any line force-prefixed with `.` | All caps emitted; case-insensitive parse. Force-prefix preserved on round-trip via the `Penova-Force-Heading:` extension when the original line wasn't natively recognizable. |
| `.action`          | A run of unindented, non-blank, non-classified lines | Multi-line action joins on `\n`. |
| `.character`       | All-caps line, ≤38 chars, followed by non-blank line; or `@`-prefixed | The `@` prefix preserved when the cue contains lowercase letters. `(CONT'D)` and `(V.O.)` suffixes preserved verbatim. |
| `.parenthetical`   | Line wrapped in `(` `)` between character cue and dialogue | Whitespace-only inside `()` collapsed to nothing on emit. |
| `.dialogue`        | Non-blank lines following a character cue or parenthetical | Lyric lines (Fountain `~` prefix) preserved as dialogue with the `~` retained. |
| `.transition`      | All-caps line ending in `:` or matching `FADE OUT.` | Right-aligned in the renderer. `> CUT TO: <` (centered) is treated as `.actBreak`, NOT `.transition`. |
| `.actBreak`        | Centered text: `> TEXT <` | Penova-specific use — Fountain spec calls this "centered text"; we co-opt it for act breaks. Custom centered text users want for non-act content uses `Penova-Centered:` note (extension). |

### Heading components

Headings split into `(SceneLocation, locationName, SceneTimeOfDay)` via
`FountainHeadingSplit.split(_:)`. The split preserves:

- **Location prefix:** `INT.`, `EXT.`, `EST.`, `INT./EXT.`
- **Separator:** ` - `, ` — `, or ` – ` (em-dash, en-dash both accepted; em-dash emitted)
- **Time-of-day:** `DAY`, `NIGHT`, `DAWN`, `DUSK`, `MORNING`, `EVENING`,
  `CONTINUOUS`, `LATER`. Unknown times default to `DAY` and are stamped
  with a `Penova-Time-Raw:` note (see _Extensions → Per-element notes_)
  so the original string survives a round-trip.

### Character cue suffixes

Standard suffixes (`(CONT'D)`, `(V.O.)`, `(O.S.)`, `(O.C.)`) carry on
the `.character` element's text verbatim. They are NOT separate
parentheticals.

## Extensions to the spec

### 1. Penova-namespaced title-page keys

All Penova-specific title-page metadata uses the prefix `Penova-`. This
means every standard Fountain reader (Highland, Slugline, Beat) sees
them as unknown keys per fountain.io's documented behavior: *"unsupported
key values… will be ignored, but you may find them useful as metadata."*

### 2. Per-element notes (`[[ … ]]`)

Fountain's note syntax `[[ note text ]]` is documented as inline writer
notes that the renderer can suppress. Penova co-opts a key:value form
inside notes to attach metadata to specific elements:

```
[[Penova: beat=midpoint]]
[[Penova: lastRevised=4F2A8B…]]
[[Penova: timeRaw=ROOFTOP]]
[[Penova: actNumber=2]]
```

A note that **doesn't** start with `Penova:` is preserved as a writer's
note on the element. Multiple `Penova:` notes can attach to one element;
they accumulate.

| Field                          | Source                                      | Where it attaches |
| ------------------------------ | ------------------------------------------- | ----------------- |
| `[[Penova: beat=...]]`         | `ScriptScene.beatType`                      | After scene heading |
| `[[Penova: actNumber=...]]`    | `ScriptScene.actNumber`                     | After scene heading |
| `[[Penova: timeRaw=...]]`      | `ScriptScene.time` when not a known enum    | After scene heading |
| `[[Penova: lastRevised=...]]`  | `SceneElement.lastRevisedRevisionID`        | Before the element |
| `[[Penova: bookmarked=true]]`  | `ScriptScene.bookmarked`                    | After scene heading |
| `[[Penova: sceneNumber=N]]`    | scene's locked number from `Project.lockedSceneNumbers` | After scene heading |

Note: the standard Fountain syntax `#42#` for explicit scene numbers is
also supported for round-trip with other tools — readers prefer the
standard form when both are present.

### 3. Boneyard for episode boundaries

Penova projects can have multiple episodes (TV shows). Fountain has no
episode concept. We use boneyard comments to demarcate:

```
/* Penova-Episode: 1 — Pilot — status=draft */

INT. KITCHEN - DAY

…

/* Penova-Episode: 2 — Breaking Point — status=draft */

INT. CAR - NIGHT

…
```

The format is `/* Penova-Episode: <order> — <title> — status=<status> */`
on a single line. A boneyard not matching this prefix is preserved as a
plain Fountain comment (writer notes inside the script).

### 4. Revision history blob

Production drafts carry a revision history. The full history serializes
as a `Penova-Revisions:` title-page key whose value is a JSON array, one
object per revision:

```
Penova-Revisions: [
   {"id":"4F2A8B…","label":"Production Draft","color":"white","roundNumber":1,
    "createdAt":"2025-10-15T10:30:00Z","authorName":"Rudra","sceneCount":42,
    "wordCount":15800,"note":""},
   {"id":"7C1D9F…","label":"Blue Revision","color":"blue","roundNumber":2,
    "createdAt":"2025-11-02T14:00:00Z","authorName":"Rudra","sceneCount":42,
    "wordCount":15920,"note":"Studio notes pass"}
]
```

The continuation-line indent is the standard 3 spaces. The Fountain
snapshot of *each* revision is **not** stored inside this blob — that's
expensive (every revision could be 100KB of script) and redundant given
the live document is in the same file. Restoration of an old revision
becomes "clone the file as it was at this Git commit" — Fountain plain
text + Git is the natural pairing.

### 5. Title-page revision running list

The title-page renderer surfaces the revision history as a stack:
```
PRODUCTION DRAFT       15 Oct 2025
BLUE REVISION          02 Nov 2025
```
This is a visual rendering only — the source of truth is the
`Penova-Revisions:` JSON above. The exporter does not write the visual
stack as text; the renderer composes it at draw time.

## Round-trip matrix

| Model field                                | Round-trips? | How |
| ------------------------------------------ | ------------ | --- |
| `Project.id`                               | **no**       | Regenerated per import. Fountain has no canonical doc-ID. |
| `Project.title`                            | yes          | `Title:` |
| `Project.logline`                          | yes          | `Notes:` (legacy) — also surfaces in `TitlePage.notes` |
| `Project.genre`                            | yes          | `Penova-Genre: drama, thriller` |
| `Project.status`                           | yes          | `Penova-Status: active` |
| `Project.trashedAt`                        | **no**       | Trashed projects don't export. |
| `Project.createdAt`                        | **no**       | Regenerated per import. |
| `Project.updatedAt`                        | **no**       | Regenerated per import. |
| `Project.contactBlock`                     | yes          | `Contact:` (multi-line) |
| `Project.locked`                           | yes          | `Penova-Locked: true` |
| `Project.lockedAt`                         | yes          | `Penova-Locked-At: 2026-05-01T12:00:00Z` |
| `Project.lockedSceneNumbers`               | yes          | `Penova-Locked-Numbers: {"sceneId":N,…}` (also via `[[Penova: sceneNumber=N]]`) |
| `Project.titlePageData`                    | yes          | All standard keys + `Penova-Draft-Stage:` |
| `Project.episodes`                         | yes          | `/* Penova-Episode: … */` boneyard delimiters |
| `Project.characters`                       | partial      | Names recovered from cue lines on import; full ScriptCharacter rows (role, age, traits, notes) emit as `Penova-Characters:` JSON title-page blob (extension) |
| `Project.revisions`                        | partial      | Metadata in `Penova-Revisions:` JSON; per-revision script snapshots are NOT stored inline (use Git or revision-folder mode) |
| `Episode.id`                               | **no**       | Regenerated. |
| `Episode.title`                            | yes          | In the boneyard delimiter |
| `Episode.order`                            | yes          | In the boneyard delimiter |
| `Episode.status`                           | yes          | In the boneyard delimiter |
| `ScriptScene.id`                           | **no**       | Regenerated. |
| `ScriptScene.heading`                      | yes          | Scene heading line |
| `ScriptScene.location`                     | yes          | Heading prefix |
| `ScriptScene.locationName`                 | yes          | Heading body |
| `ScriptScene.time`                         | yes          | Heading suffix; unknown values via `[[Penova: timeRaw=…]]` |
| `ScriptScene.sceneDescription`             | yes          | First Action element after the heading (legacy compat) |
| `ScriptScene.order`                        | yes          | Document order |
| `ScriptScene.beatType`                     | yes          | `[[Penova: beat=midpoint]]` |
| `ScriptScene.actNumber`                    | yes          | `[[Penova: actNumber=2]]` |
| `ScriptScene.bookmarked`                   | yes          | `[[Penova: bookmarked=true]]` |
| `ScriptScene.createdAt`                    | **no**       | Regenerated. |
| `ScriptScene.updatedAt`                    | **no**       | Regenerated. |
| `SceneElement.id`                          | **no**       | Regenerated. |
| `SceneElement.kind`                        | yes          | Body syntax — every kind has a Fountain form |
| `SceneElement.text`                        | yes          | Body content |
| `SceneElement.order`                       | yes          | Document order |
| `SceneElement.characterName`               | yes          | Recovered from preceding `.character` |
| `SceneElement.lastRevisedRevisionID`       | yes          | `[[Penova: lastRevised=…]]` before the element |
| `Revision.id`                              | yes          | Inside `Penova-Revisions:` JSON |
| `Revision.label`                           | yes          | JSON |
| `Revision.color`                           | yes          | JSON |
| `Revision.roundNumber`                     | yes          | JSON |
| `Revision.fountainSnapshot`                | **no**       | Stored externally (Git or `.penova-revisions/` folder); not inlined |
| `Revision.createdAt`                       | yes          | JSON ISO-8601 |
| `Revision.authorName`                      | yes          | JSON |
| `Revision.sceneCountAtSave`                | yes          | JSON |
| `Revision.wordCountAtSave`                 | yes          | JSON |
| `WritingDay.*`                             | **no**       | Per-user, per-device habit tracking; never round-trips through Fountain by design (privacy + portability) |

## Forward compatibility

- A Penova v1.3 reader opening a v1.2 file: every v1.2 field is a v1.3
  field. Forward compat by definition.
- A Penova v1.2 reader opening a v1.3 file: unknown `Penova-` title-page
  keys go into `ParsedDocument.unknownTitleKeys`. Unknown `[[Penova:
  fooBar=…]]` notes go into `ParsedElement.unknownNotes`. Both survive
  the round-trip when the v1.2 reader exports back to Fountain — older
  Penova versions don't *use* the new fields, but they don't lose them
  either.
- A non-Penova reader (Highland / Slugline / Beat) opening a Penova
  file: every standard Fountain element renders correctly. Penova
  extensions appear as either unknown title-page keys (silently ignored
  per the spec), boneyard comments (visible in the source but suppressed
  in the formatted view), or notes (suppressed in print).

## Test contract

The round-trip property test is:

```swift
@Test func projectRoundTripsLosslessly(seed: UInt64) {
    let original = makeRandomProject(seed: seed)
    let exported = FountainExporter.export(project: original)
    let parsed = FountainParser.parse(exported)
    let reimported = FountainImporter.makeProject(...)
    let reExported = FountainExporter.export(project: reimported)
    #expect(exported == reExported)  // structural equivalence
    #expect(reimported.matches(original))  // semantic equivalence
}
```

Run across 100+ seeds with varied project shapes: 1-scene, 100-scene,
multi-episode, locked-with-revisions, every BeatType, custom time-of-day
strings, all-empty-title-page, full-title-page, etc.

A field is considered "round-trippable" only when the property test
passes for it. The matrix above lists every field's status.

## Phase plan

This document describes the **target state** (Phase 1 complete + Phase 2
extension parsing). Implementation rolls out across multiple PRs:

- **Phase 1** (this PR): document the spec; add the round-trip property
  test scaffold; identify gaps in the current implementation. The
  `Penova-` title-page keys and `[[Penova: …]]` element notes are
  parsed/emitted for the high-priority fields (genre, status, locked,
  beatType, lastRevisedRevisionID).
- **Phase 2** (follow-up): close every "no" or "partial" row in the
  matrix above where a "yes" is achievable. Lift the round-trip property
  test to assert structural equivalence for all 100+ random projects.
- **Phase 3** (later): "Fountain folder mode" — Settings toggle that
  switches Penova from SwiftData-as-source-of-truth to Fountain-as-
  source-of-truth, with SwiftData becoming an indexing/cache layer.
- **Phase 4**: Windows port. Reads the same spec.

## Why not just use `.fdx`?

Final Draft's XML format is structured and round-trips well, but:
1. It's not human-readable. A Windows port would have to ship a
   sophisticated XML viewer to debug user issues.
2. It's not Git-friendly. Diffing two FDX files for "what changed" is
   useless without a custom XML diff tool.
3. The spec isn't formally published. Final Draft can change the schema
   in v14 and break our parser.
4. Fountain has industry mindshare in the indie + open-source corner
   that Penova lives in. Highland users, Beat users, KIT Scenarist users
   already have Fountain workflows.

`.fdx` remains an export and import target for round-trip with Final
Draft users; it's not the canonical at-rest format.
