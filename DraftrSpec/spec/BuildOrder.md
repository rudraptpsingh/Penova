# Build Order — Draftr v0.1 (Swift / SwiftUI)

Ship-path to MVP. Each milestone should leave the app compiling, launchable, and demoable.

## Milestone 0 — Project scaffold (Day 0–1)

- [ ] Xcode project: iOS 17+, SwiftUI App lifecycle, Swift 5.10
- [ ] Register Inter + Roboto Mono via `Info.plist` → `UIAppFonts`
- [ ] Drop in `DesignTokens.swift`, `Icons.swift`, `Copy.swift`, `Models.swift`, `FreemiumLimits.swift`
- [ ] Add SVG icons to asset catalog as "Single Scale" vectors with "Preserve Vector Data" + "Template Image" render mode
- [ ] Configure SwiftData `ModelContainer` in `@main` App
- [ ] Force `.preferredColorScheme(.dark)` on root
- [ ] Smoke-test: app launches, prints tokens, no crashes

## Milestone 1 — Design system components (Day 1–3)

Build `Components.swift` reusable primitives before any screen:

- [ ] `DraftrButton` (primary / secondary / ghost / destructive variants)
- [ ] `DraftrTag` (capsule with paper bg, labelTiny caps text)
- [ ] `DraftrChip` (selectable filter)
- [ ] `DraftrTextField` (with label + error state)
- [ ] `DraftrSectionHeader` (uppercase labelCaps + divider)
- [ ] `ProjectCard`, `ScriptItem`, `CharacterCard`, `SceneItem`
- [ ] `EmptyState` (icon + headline + body + CTA)
- [ ] `CuePill` (slate dot + slate text)
- [ ] SwiftUI previews for each in light-off / dark mode

## Milestone 2 — Auth & onboarding (Day 3–5)

- [ ] S01 Splash (320ms fade)
- [ ] S02 Onboarding pages with `TabView(.page)`
- [ ] S03 Sign in with Apple (`AuthenticationServices.SignInWithAppleButton`)
- [ ] Store user in SwiftData; skip to S04 on relaunch if authed

## Milestone 3 — Projects & episodes (Day 5–8)

- [ ] S04 Home (greeting by time, project cards, FAB)
- [ ] S05 Project detail (episode list, metadata, actions)
- [ ] S06 New Project sheet (name, genre, description)
- [ ] S07 Episodes list + new episode sheet
- [ ] Freemium gate: block project #2 on free → S20

## Milestone 4 — Scenes & editor (Day 8–14)  [**highest risk**]

- [ ] S08 Scene list (+ swipe actions)
- [ ] S09 New Scene sheet (location/time of day pickers)
- [ ] S10 Scene detail (beat/elements list)
- [ ] S11 **Editor** — mono font, inline element type toolbar, autosave
- [ ] S12 Element Type sheet (Action/Dialogue/Parens/Transition)
- [ ] Freemium gate: 15 scenes max on free → S22

## Milestone 5 — Characters & search (Day 14–17)

- [ ] S14 Characters grid (2-col)
- [ ] S15 Character detail (role, age, bio)
- [ ] S16 Global scenes list
- [ ] S17 Scene search with filter chips (`.searchable`)

## Milestone 6 — Export & Pro (Day 17–21)

- [ ] PDF export via `PDFKit`, screenplay formatting (mono 12pt, Courier-like spacing)
- [ ] FDX export (Pro only; XML writer)
- [ ] `ShareLink` share sheet
- [ ] StoreKit 2 products, purchase, entitlements
- [ ] S20 Paywall sheet
- [ ] S22 Limit-reached sheet

## Milestone 7 — Quick Capture & polish (Day 21–26)

- [ ] S19 Quick Capture sheet with `SFSpeechRecognizer`
- [ ] Microphone permission prompt
- [ ] S18 Settings (account, subscription, about, sign out)
- [ ] S21 Delete confirm dialog
- [ ] Accessibility pass (VoiceOver labels, Dynamic Type, Reduce Motion)
- [ ] Empty states (Section G copy strings)

## Milestone 8 — Ship (Day 26+)

- [ ] App Store Connect setup
- [ ] Screenshots (use Xcode 15 simulator screenshot tool)
- [ ] Review & submit
- [ ] TestFlight beta

## Risk register

| Risk | Mitigation |
|---|---|
| Editor performance on long scenes | Use `TextEditor` with lazy rendering; paginate if >10k chars |
| Speech recognition reliability in Indian accents | Allow manual edit before save; fall back to typing |
| StoreKit sandbox quirks | Test on physical device with sandbox user early (Milestone 7 start) |
| SwiftData migration churn | Lock schema at Milestone 4; use `VersionedSchema` from day one |
