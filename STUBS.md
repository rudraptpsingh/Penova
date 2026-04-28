# Stub tracker

Every deferred piece of work has a `// STUB:` comment in code. This
file mirrors that list so we can audit what's outstanding at any time.

Run `grep -rn "STUB:" Penova PenovaSpec` to refresh the list.

## Convention

- Use `// STUB:` (exact casing) in code.
- When you remove a stub, also delete the matching row here.

## Current stubs

The MVP is fully functional. The two remaining stubs are explicitly
post-1.0 and don't gate App Store submission.

| File | Line | What's deferred | Why it's not a blocker |
|------|------|-----------------|------------------------|
| `Penova/Features/QuickCapture/VoiceCaptureSheet.swift` | file header | Live waveform, partial-result smoothing, locale picker, offline-only toggle | Core dictation + save path is fully functional. Cosmetic polish only. |
| `Penova/Features/Onboarding/OnboardingScreen.swift` | `handleAppleResult` | Server-side Apple nonce exchange + account linking | App is offline-first; SiA credentials land in UserDefaults so the user's name shows in Settings. Real exchange waits for the cloud-sync milestone. |

## Resolved

| When | Stub | Resolution |
|------|------|-----------|
| pre-1.0 | `Paywall/PaywallSheet.swift` | Removed entirely — no freemium gates ship in 1.0. |
| pre-1.0 | `ProjectDetailScreen.swift exportFDX()` | Shipped — `FinalDraftXMLWriter` is the production exporter. |
| pre-1.0 | `Settings/SettingsScreen.swift` subscription block | Removed — no subscription state ships in 1.0. |
| pre-1.0 | `NewSceneSheet.swift` "hook into continuous editor" TODO | Continuous editor (`SceneDetailScreen` + `EditorLogic`) shipped; TODO removed. |
