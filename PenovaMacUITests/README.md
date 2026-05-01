# PenovaMacUITests

XCUITest scenarios that drive the running Mac app. They cover the screenwriter
workflows research surfaced as highest-priority for v1:

- `test01_launchShowsThreePaneShell` — sidebar + editor + inspector visible
- `test02_sidebarHasSeededProject` — sample library populated on first run
- `test03_viewModeToggle` — Editor → Index Cards → Outline cycle
- `test04_searchOverlay` — ⌘F overlay opens, accepts query, dismisses on Esc
- `test05_exportSheetOpens` — ⌘E shows three formats, dismisses correctly
- `test06_titlePageEditorOpens` — ⌘⇧T sheet
- `test07_coldLaunchIsFast` — XCTApplicationLaunchMetric < 4s

## Running locally

```sh
xcodebuild -project Penova.xcodeproj -scheme PenovaMac \
  -destination 'platform=macOS' test
```

## Permissions

XCUITest's runner needs **Accessibility** permission to drive the
Penova window. macOS will prompt the first time:

System Settings → Privacy & Security → Accessibility →
allow `PenovaMacUITests-Runner.app` (or `Xcode`).

Without this you'll see:

> Failed to initialize for UI testing: Authentication cancelled. System authentication is running.

This is a one-time grant per machine.

## Accessibility identifiers

Tests find views via stable identifiers declared in
`PenovaMac/App/PenovaLog.swift` (`A11yID` enum) and applied via
`.accessibilityIdentifier(...)` in each Mac view. Keep the two in sync.

## Realism

Test scenarios are derived from documented screenwriter routines —
Mira's resume-and-write, Diego's jump-to-scene, Priya's FDX export,
Sam's index-card rewrite, Ana's crash recovery. Sources: Scriptnotes
podcast archives, Final Draft KB, Highland 2 docs, WGAW member essays.
