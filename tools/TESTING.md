# Testing strategy for Penova

This document explains what we test automatically, what we test manually,
and what to do when a bug ships anyway.

## The honest baseline

Penova has 443+ unit tests across 46 suites as of v1.2.1. The coverage
is heavily concentrated on:

- **Parsers and exporters** (Fountain, FDX, PDF) — round-trip correctness
- **Models and SwiftData** — schema, migrations, persistence semantics
- **Specific feature logic** — (CONT'D) auto-insert, character rename,
  page locking, revision colors, smart paste detection
- **Real-world fixtures** — Big Fish, Brick & Steel, The Last Birthday
  Card screenplays parse and round-trip cleanly

What's **not** in those numbers, and what bit us in v1.1.x → v1.2.1:

- **SwiftUI view rendering** — there's no easy way to assert "the
  `kindBadge` chip overlaps the `CUT TO:` text" from a unit test. The
  user's eyes caught it; we shipped it; we fixed it; we now have a
  source-grep regression test (`RegressionsV1Tests`) that fires if the
  chip ever comes back, but the original bug landed because nobody had
  written that test.
- **Window layout math** — `WindowGroup.frame(minWidth:)` interactions
  with macOS's saved frame state are nuanced and only visible with a
  running app on a small enough screen.
- **Release-pipeline output** — `tools/sign-update.sh`'s emitted
  appcast item, the Cloudflare Pages deploy, Sparkle's signature
  validation: all real moving pieces, none fully covered.

When a bug surfaces from manual testing or a user report, the first
question now is: **"could a unit test have caught it?"** If yes, write
the test alongside the fix in `RegressionsV1Tests.swift`. The bug then
graduates from "we missed it once" to "this can never come back."

## What CI runs on every PR

`.github/workflows/ci.yml` runs on every push to a non-main branch and
every PR against main:

1. **Static checks** (no Xcode needed) — `appcast.xml` parses as
   well-formed XML; every `Info.plist` parses; `project.yml` parses.
   Catches the v1.1.0 `--`-in-comment bug shape without running the
   test suite.
2. **Build PenovaMac** — `xcodebuild build` for `platform=macOS`. Fails
   the PR if the Mac target won't compile.
3. **Build Penova** — same for `platform=iOS Simulator,name=iPhone 17 Pro`.
4. **Run PenovaTests** — full unit-test sweep on the iOS simulator.
   Result bundle uploaded as an artifact on failure for triage.

Total runtime: ~5 minutes for static checks + ~15-20 minutes for the
Xcode build/test job. Fits comfortably under GitHub's 2,000 free
private-repo minutes per month at typical PR cadence.

## What CI does NOT cover (by design)

- **No code signing.** The Developer ID cert lives in a separate
  secret-protected workflow (`.github/workflows/release.yml`) that runs
  only on tag push. CI builds use the runner's ad-hoc signing.
- **No notarization.** Same reason — only the release workflow uses
  the notarytool credentials.
- **No deployment.** Cloudflare Pages deploys are triggered only by
  the release workflow.
- **No UI-tree assertions.** We don't run `XCUITest` in CI today;
  the SwiftUI surface is hard to introspect cleanly. The
  `accessibilityIdentifier` constants in `PenovaKit/Sources/PenovaKit/AccessibilityIdentifiers.swift`
  are in place for when a future UI-test suite lands.

## Manual smoke-test checklist

Before tagging a release, walk through this checklist on a real Mac
with the freshly built DMG. Each item is a known-bug shape that no
unit test currently catches.

### Editor

- [ ] Open a project. Click anywhere in the script panel — paper
      should fit without horizontal scrolling at the default window
      size (1380×880 or wider).
- [ ] Drag the window narrower until you hit the minimum width
      (~1280pt). Paper should still fit; layout should not break.
- [ ] Click on a `CUT TO:` transition row. Confirm no
      `TRANSITION` chip overlaps the right-aligned text.
- [ ] Click on a regular Action row, then a Character cue, then
      Dialogue. The visible row should look like a screenplay (no
      inline element-kind labels).
- [ ] Type two consecutive `JANE` cues separated by an action line.
      The second should auto-become `JANE (CONT'D)`.
- [ ] Insert above a row, then delete that row, then insert above
      again. Repeat 5×. Close and reopen the project. Row order
      should match what you saw before closing.
- [ ] On a brand-new scene, tap "Start writing." The first inserted
      element should be an empty Action row, not a duplicate scene
      heading.

### Sparkle update flow (the hard one)

- [ ] On a Mac with the previous shipped version installed, run
      `Penova → Check for Updates…`. The "A new version is available"
      dialog should appear within a few seconds.
- [ ] Click Install. The download should succeed (no "improperly
      signed" or "could not validate" error).
- [ ] After install, `Penova → About` should show the new version.
- [ ] Auto-check timing: leave the app running for an hour after a
      release. The update prompt should appear automatically without
      clicking Check for Updates first (per the
      `SUScheduledCheckInterval=3600` setting).

### File interop

- [ ] Export a project to FDX. Open it in Final Draft. Title page,
      scenes, and dialogue should render cleanly.
- [ ] Export a project to Fountain. Open the `.fountain` file in
      Highland 2 or Beat. Title page and body should render.
- [ ] Import a `.fdx` file (try one of the fixtures in
      `PenovaTests/Fixtures/screenplays`). Scenes and characters
      should appear correctly.
- [ ] Import a PDF screenplay. Scenes should be recognized; dialogue
      should be attributed to characters.

### Title page

- [ ] On iOS, open the Title Page editor. Tap into the multi-line
      Contact field. Type 4 lines. Verify the Save button doesn't
      hide behind the keyboard. Drag down to dismiss the keyboard.
- [ ] On Mac, open the Title Page sheet, fill in every field. Save
      and re-open. Every field should round-trip.

### Voice capture (iOS only)

- [ ] Tap the microphone icon. Grant permissions on first use.
      Speak a short scene. Release. The transcribed text should
      land in a draft. Try `en-IN`, `en-US`, `hi-IN` locales.

## Adding a new test for a shipped bug

When fixing a bug that slipped past CI:

1. Add a test in `PenovaTests/RegressionsV1Tests.swift` (or a sibling
   `RegressionsVN.swift` for a future major version).
2. Test name: `xxx_DoesNotXxx` or `xxx_DoesXxx` — describe the
   contract, not the bug.
3. Doc-comment block above the test: link to the version it shipped
   in, the user-visible symptom, and a one-line fix description. This
   becomes the maintenance trail for that test.
4. The test should be **small** — assert the exact symptom the user
   saw, not the underlying mechanism. That way it survives
   refactoring and stays readable.
5. Run `xcodebuild test -only-testing:PenovaTests/RegressionsV1Tests`
   locally before pushing.
6. The CI workflow runs it on the PR; merge once green.

## Future test surfaces (deferred)

- **Snapshot testing** for SwiftUI views (e.g. swift-snapshot-testing
  by pointfree.co). Would catch the kindBadge overlap directly.
  Worth adopting in v1.3 once we have a SwiftUI-stable view hierarchy.
- **XCUITest end-to-end flows** — open app, create scene, type
  dialogue, export PDF, verify file content. Slow but catches
  integration bugs the unit tests miss.
- **Property-based testing** via swift-testing's parameterized tests.
  We have a few in the Fountain dialect tests; extend to PDF
  rendering, character rename, smart paste.
- **Sparkle update simulation** — spin up a local HTTP server with a
  controlled appcast + DMG, point a debug-built Penova at it, run
  through the update flow programmatically.

When any of these is worth the engineering investment, it goes into
its own PR.
