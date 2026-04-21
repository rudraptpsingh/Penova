# SwiftUI Mapping — Draftr v0.1

Everything in the Figma spec mapped to native Apple primitives. Use this as the translation table when implementing.

## Global

| Spec concept | Apple primitive |
|---|---|
| Dark-only theme | `.preferredColorScheme(.dark)` on root `WindowGroup` |
| Colour tokens | `Color` extensions in `DesignTokens.swift` (do **not** use asset catalog — tokens are code) |
| Inter / Roboto Mono fonts | Register via `Info.plist` `UIAppFonts`, expose through `DraftrFont.*` |
| 8pt spacing ladder | `DraftrSpace.*` (xs=4, s=8, sm=12, m=16, l=24, xl=40, xxl=64) |
| Radius 8 / 12 / ∞ | `DraftrRadius.sm` / `.md` / `.full` via `.clipShape(RoundedRectangle(cornerRadius:))` or `.clipShape(Capsule())` |
| Motion 120 / 200 / 320 ms | `DraftrMotion.fast` / `.base` / `.slow` using `Animation.timingCurve(0.2, 0.8, 0.2, 1, duration:)` |
| Haptics on publish / save | `.sensoryFeedback(.success, trigger:)` (iOS 17+) |
| Dynamic Type | Use `Font` with size presets + `.dynamicTypeSize(.medium ... .xxxLarge)` clamp |
| Reduce Motion | `@Environment(\.accessibilityReduceMotion)` → disable parallax & decorative animation |

## Navigation

| Spec | Apple primitive |
|---|---|
| 21-screen flow | Single `NavigationStack` per tab, switched by root `TabView` |
| Bottom nav (Home / Scripts / Characters / Scenes) | `TabView` with 4 tabs, `.tabViewStyle(.automatic)` |
| Modal sheets (S19 Quick Capture, S20 Paywall, S22 Limit) | `.sheet(isPresented:)` + `.presentationDetents([.medium, .large])` with `.presentationDragIndicator(.visible)` |
| Full-screen editor (S11) | Push onto `NavigationStack`, hide tab bar via `.toolbar(.hidden, for: .tabBar)` |
| Delete confirm (S21) | `.confirmationDialog` (not `.alert`) for destructive action |
| Back chevron | `NavigationStack` default back; customise label if needed with `.navigationTitle` + `.navigationBarBackButtonHidden` + toolbar |

## Data & Storage

| Spec | Apple primitive |
|---|---|
| Projects / Episodes / Scenes / Elements | **SwiftData** `@Model` classes (iOS 17+) — one-to-many relations with `@Relationship(deleteRule: .cascade)` |
| Local-first, offline | SwiftData's on-device store; no CloudKit sync in v0.1 |
| Character bible | SwiftData model; derive `ProjectCharacters` via `@Query` with predicate |
| Usage metrics (project count, scene count) | `@Model UsageMetrics` |
| Draft autosave | Debounced `.onChange(of: scene.body)` → `modelContext.save()` every ~500ms |

## Billing

| Spec | Apple primitive |
|---|---|
| Freemium gating | `FreemiumCheck` struct reads SwiftData `UsageMetrics` + `Subscription` |
| Pro subscription | **StoreKit 2** `Product.products(for:)` + `purchase()` + `Transaction.currentEntitlements` listener |
| Paywall (S20) | Sheet with `Product` fetch; on success flip `user.subscription.plan = .pro` |
| Restore purchases | `AppStore.sync()` |

## Features

| Spec feature | Apple primitive |
|---|---|
| Voice-to-text (Quick Capture S19) | **`Speech`** framework (`SFSpeechRecognizer`) + `AVAudioEngine` microphone tap |
| PDF export (S15) | `PDFKit` to render formatted script; `ShareLink(item: pdfURL)` for share sheet |
| FDX export (Pro) | Custom XML writer; `ShareLink` |
| Search (S04) | `.searchable(text:)` on `NavigationStack` root |
| Pull-to-refresh | `.refreshable { ... }` |
| Tag pills | `DraftrTag` (`RoundedRectangle(cornerRadius: DraftrRadius.sm)` filled with `DraftrColor.ink3`) |
| Bottom sheet handle | `.presentationDragIndicator(.visible)` |

## Per-screen primitive map

| ID | Screen | Container | Notable primitives |
|---|---|---|---|
| S01 | Splash | `ZStack` | `.transition(.opacity)` with 320ms timing |
| S02 | Onboarding | `TabView(.page)` | Page-style TabView with dots |
| S03 | Sign-in | `Form` styled custom | `SignInWithAppleButton` (AuthenticationServices) |
| S04 | Home | `NavigationStack` + `ScrollView` | `.searchable`, `LazyVStack` of project cards |
| S05 | Project Detail | `NavigationStack` push | Section headers = `Text("...").textCase(.uppercase)` |
| S06 | New Project | `.sheet` | `Form` with `TextField`, `Picker` for Genre |
| S07 | Episodes List | push | `List` with `.listStyle(.plain)` |
| S08 | Scene List | push | `List` with swipe `.swipeActions` (Delete, Bookmark) |
| S09 | New Scene | `.sheet` | `Picker` for Location/TimeOfDay |
| S10 | Scene Detail | push | Custom vertical stack with element rows |
| S11 | Editor | push (fullscreen) | `TextEditor` with mono font + toolbar keyboard accessory |
| S12 | Element Type Sheet | `.sheet` with `.medium` detent | Grid of element type buttons |
| S14 | Characters List | `NavigationStack` | `LazyVGrid` 2-col |
| S15 | Character Detail | push | `Form`-like sections |
| S16 | Scenes List (global) | `NavigationStack` | Same as S08 but across all projects |
| S17 | Scene Search | `.searchable` | Filter chips row above list |
| S18 | Settings | push | `List` with `.listStyle(.insetGrouped)` |
| S19 | Quick Capture | `.sheet` | `Speech` framework recording |
| S20 | Paywall | `.sheet` with `.large` detent | `StoreKit` `ProductView` or custom |
| S21 | Delete Confirm | `.confirmationDialog` | Destructive button style |
| S22 | Limit Reached | `.sheet` with `.medium` detent | CTA to S20 |

## Accessibility

- Every custom icon: `.accessibilityLabel(...)`
- Every tap target: min 44×44 pt (use `.frame(minWidth: 44, minHeight: 44)`)
- Support `.accessibilityLargeContentViewer` for Script content (mono font 13pt is below 17pt minimum otherwise)
- `VoiceOver` announcement on save success via `.accessibilityAnnouncement`
