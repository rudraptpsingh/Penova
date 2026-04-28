# Shipping Penova to the App Store

This file captures the steps needed to turn the current source tree into a
TestFlight / App Store build. Nothing here is automated — every item is a
manual action the owner (Apple ID + team membership) has to take in Xcode
or App Store Connect.

## 1. Before you open Xcode

- [ ] Confirm Apple Developer Program membership is active.
- [ ] Bundle ID `com.rudrapratapsingh.penova` is registered in Certificates,
      Identifiers & Profiles with the **Sign in with Apple** capability on.
- [ ] An App record exists in App Store Connect with the same bundle ID,
      name "Penova", primary language English (UK), category **Productivity**
      (secondary: Entertainment).

## 2. One-off project edits (done in this repo)

- `MARKETING_VERSION` = **1.0.0**, `CURRENT_PROJECT_VERSION` = **1**
  (bump `CURRENT_PROJECT_VERSION` every TestFlight upload).
- `Info.plist` carries:
  - `ITSAppUsesNonExemptEncryption = false` — skips the export-compliance wizard.
  - `UIRequiredDeviceCapabilities = [arm64]`.
  - `UILaunchScreen` present (pure-black fallback — the SwiftUI splash takes
    over from there).
  - `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`
    strings for Quick Capture.
- `PrivacyInfo.xcprivacy` declares zero tracking, zero data collection, and
  required-reason codes for UserDefaults (`CA92.1`), file timestamp
  (`C617.1`), disk space (`E174.1`), system boot time (`35F9.1`).
- `Penova.entitlements` enables **Sign in with Apple**.
- `AppIcon.appiconset` contains a single universal 1024×1024 PNG
  (`icon-1024.png`) — Xcode generates every runtime size from it.

## 3. In Xcode, one-time per machine

1. Open `Penova.xcodeproj`.
2. Select the `Penova` target → **Signing & Capabilities**:
   - Tick **Automatically manage signing**.
   - Pick the correct Team.
   - Keep **Sign in with Apple** capability.
3. Select **Product → Destination → Any iOS Device (arm64)**.
4. **Product → Archive**.

## 4. Upload

1. In the Organizer window that appears after archive: **Distribute App →
   App Store Connect → Upload**.
2. Let Xcode generate symbols and upload.
3. In App Store Connect, once the build finishes processing (~15 min), add
   it to the TestFlight internal group for smoke-testing, then submit for
   App Review when ready.

## 5. App Store metadata to prepare

The code ships the product; this copy ships the listing.

- **App name:** Penova
- **Subtitle:** Write the page. Hide the app.
- **Promotional text (170 chars):** A dark-first screenplay editor built
  for phones. INT/EXT scenes, clean mono dialogue, one-tap industry-format
  PDF. Offline. No accounts required.
- **Description:** see `docs/app-store-description.md` (write before submit).
- **Keywords:** screenplay, screenwriter, script, writing, dialogue,
  scene, storyboard, PDF, mobile writer, draft.
- **Primary category:** Productivity. Secondary: Entertainment.
- **Age rating:** 4+ (no UGC that's surfaced to other users, no ads, no
  tracking).
- **Privacy → Data Collection:** *No data is collected from this app.*
- **Sign in with Apple:** required — note in review notes that the current
  build stores the Apple credential in UserDefaults only; no backend.

## 6. Screenshots (required set)

Take on a 6.7" iPhone simulator (e.g. iPhone 17 Pro), portrait:
1. Splash + tagline.
2. Home — greeting + writing-streak card + seeded project card.
3. Scene detail — industry-formatted screenplay ladder.
4. Scripts tab — empty state showing the "Already have a script? PDF · FDX · Fountain" import card.
5. Quick Capture voice sheet (mid-dictation).
6. Habit dashboard — today's words, streak, 49-day heatmap.
7. Export menu with PDF / FDX / Fountain options surfaced.

Also export one 6.9" set (iPad Pro 12.9") for the iPad listing — the layout
works portrait as-is because we allow iPad rotation in project.yml.

## 7. Review notes to paste into App Store Connect

> Penova is a single-player offline screenplay editor. Sign in with Apple
> is offered for a future sync feature but is not required to use the app
> — the user can dismiss onboarding and proceed. The microphone + speech
> recognition permissions are used only when the user explicitly taps the
> microphone icon for "Quick Capture" — no background recording.
>
> Onboarding for existing scripts: tap Scripts tab → top-right `+` →
> "Import script…" (or use the empty-state card). The picker accepts
> `.pdf`, `.fdx`, `.fountain`, `.txt`, `.md`. Parser is on-device only;
> nothing is uploaded.
>
> Demo data is seeded on first launch (a sample 2-episode screenplay) so
> the reviewer can exercise every screen without authoring new content.

## 8. Post-launch

- Watch crash reports in Xcode Organizer.
- Bump `CURRENT_PROJECT_VERSION` + tag the commit for each TestFlight
  upload.
- Remaining post-1.0 polish (voice waveform, real Apple SiA backend
  exchange) is tracked in [STUBS.md](STUBS.md) — every deferred piece
  of work is a `// STUB:` comment in code.

## 9. Pre-submission readiness audit (run before each Archive)

| Check | Where to verify | Expected |
|---|---|---|
| `MARKETING_VERSION` | `project.yml` | matches App Store Connect version |
| `CURRENT_PROJECT_VERSION` | `project.yml` | bumped from previous TestFlight upload |
| `ITSAppUsesNonExemptEncryption` | `Info.plist` | `false` (skips export-compliance wizard) |
| `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` | `Info.plist` | non-empty, user-facing |
| `PrivacyInfo.xcprivacy` reasons | `Penova/Resources/PrivacyInfo.xcprivacy` | covers UserDefaults (CA92.1), file timestamp (C617.1), disk space (E174.1), boot time (35F9.1) |
| Sign in with Apple | `Penova.entitlements` | `com.apple.developer.applesignin` capability set |
| App Icon | `AppIcon.appiconset` | single 1024×1024 PNG present |
| No active `// STUB:` comments | `grep -rn "STUB:" Penova PenovaSpec` | only the two known-deferred entries in `STUBS.md` |
| All Swift files in pbxproj | `find ... -name "*.swift" \| wc -l` vs `grep -c "sourcecode.swift" project.pbxproj` | counts match |
| Tests pass | `xcodebuild test` | green; the import + round-trip suite must be green before any TestFlight upload |
| Demo data seeds on fresh install | delete app, reinstall | the "Last Train" sample screenplay is present |

## 10. Feature inventory at 1.0

| Surface | Capability |
|---|---|
| Editor | Continuous SwiftUI editor, type chips, autosave, undo, scene/character autocomplete |
| Onboarding existing material | PDF + FDX + Fountain import via `ScreenplayImporter`. Picker accepts `.pdf` / `.fdx` / `.fountain` / `.txt` / `.md`. Parser is on-device, no network. |
| Export | PDF (industry-format Courier 12, WGA indents), FDX (Final Draft 8+ XML, with title page), Fountain (round-tripped through `FountainExporter`) |
| Writing habit | Daily-word goal (`HabitTracker`), streak + best, 7×7 heatmap, auto-recorded from editor save path |
| Quick capture | On-device speech recognition + save-to-scene |
| Search | Global cross-project search (`GlobalSearchView`) |
| Characters | Many-to-many `Project ↔ ScriptCharacter`, character report with line counts |
| Privacy | No tracking, no data collection, no network calls. SwiftData store local-only. |

## Regenerating the Xcode project

`project.yml` is the source of truth. After editing it:

```sh
xcodegen
xcodebuild -project Penova.xcodeproj -scheme Penova \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

Do not hand-edit `Penova.xcodeproj/project.pbxproj` — regeneration will
overwrite it.
