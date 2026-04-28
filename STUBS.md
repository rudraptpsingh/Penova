# Stub tracker

Every deferred piece of work has a `// STUB:` comment in code. This
file mirrors that list so we can audit what's outstanding at any time.

Run `grep -rn "STUB:" Penova PenovaSpec` to refresh the list.

## Convention

- Use `// STUB:` (exact casing) in code.
- When you remove a stub, also delete the matching row here and add it
  to the Resolved table below.

## Current stubs

**None.** Penova ships 1.0 with every code path real, exercised, and
on-device.

```sh
$ grep -rn "STUB:" Penova PenovaSpec
$  # (no output)
```

## Resolved

| When | Stub | Resolution |
|------|------|-----------|
| pre-1.0 | `Paywall/PaywallSheet.swift` | Removed entirely — no freemium gates ship in 1.0. |
| pre-1.0 | `ProjectDetailScreen.swift exportFDX()` | Shipped — `FinalDraftXMLWriter` is the production exporter. PDF + FDX + Fountain all wired in `ProjectDetailScreen`. |
| pre-1.0 | `Settings/SettingsScreen.swift` subscription block | Removed — no subscription state ships in 1.0. |
| pre-1.0 | `NewSceneSheet.swift` "hook into continuous editor" TODO | Continuous editor (`SceneDetailScreen` + `EditorLogic`) shipped; TODO removed. |
| 1.0 | `VoiceCaptureSheet.swift` polish | Shipped: live waveform (RMS-driven 24-bar visualisation), partial-result smoothing (150ms throttle), locale picker (`en-IN`, `en-US`, `en-GB`, `hi-IN`), offline-only toggle (auto-disabled when the chosen locale lacks on-device support). |
| 1.0 | `OnboardingScreen.swift` Apple SiA backend | Reframed as a design decision: Penova is offline-first, no backend exists, Apple authorization completes on-device. Local credential storage IS the production artefact. The note about future server-side nonce verification moved into the file's architecture comment. |
