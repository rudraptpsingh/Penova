# Stub tracker

Every deferred piece of work has a `// STUB:` comment in code. This file
mirrors that list so we can audit what's outstanding at any time.

Run `grep -rn "STUB:" Draftr DraftrSpec` to refresh the list.

## Convention

- Use `// STUB:` (exact casing) in code. The final task of the build plan
  sweeps the codebase and fails the release if any remain unresolved.
- When you remove a stub, also delete the matching row here.

## Current stubs

All remaining stubs are deferred to the "paid features" milestone — none
are required for the offline-only v0.1 ship.

| File | Line hint | Owner | What's missing |
|------|-----------|-------|----------------|
| Draftr/Features/Paywall/PaywallSheet.swift | file header | Paid-features milestone | Real StoreKit 2 product load, purchase, restore. Sheet is currently a visual placeholder behind a feature flag — nothing in the app presents it today. |
| Draftr/Features/Project/ProjectDetailScreen.swift | `exportFDX()` | Paid-features milestone | Final Draft XML writer + temp file → ExportShareSheet reuse. Button currently shows "coming in the next release." |
| Draftr/Features/QuickCapture/VoiceCaptureSheet.swift | file header | Polish | Live waveform, partial-result smoothing, locale picker, offline-only toggle. Core dictation + save path is fully functional. |
| Draftr/Features/Onboarding/OnboardingScreen.swift | `handleAppleResult` | Paid-features milestone | Server-side Apple nonce exchange + account linking. Credentials land in UserDefaults for now — enough to show the user's name in Settings later. |
| Draftr/Features/Settings/SettingsScreen.swift | file header | Paid-features milestone | Real StoreKit subscription state + Apple account status. Subscription + usage sections are hidden behind a commented-out block until then. |

## Resolved

_(move rows here when you finish them, with the commit sha)_
