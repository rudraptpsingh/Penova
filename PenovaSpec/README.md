# PenovaSpec

Everything needed to build **Penova v0.1** — a mobile-first screenwriting app for Indian screenwriters — as a native **Swift / SwiftUI** iOS app.

> "Write the page. Hide the app."

## Stack

- **iOS 17+**, Swift 5.10, SwiftUI
- **SwiftData** (persistence)
- **StoreKit 2** (subscriptions)
- **Speech** framework (voice capture)
- **PDFKit** (export)
- **Sign in with Apple** (`AuthenticationServices`)

## Files

### Swift source
| File | Contents |
|---|---|
| [DesignTokens.swift](DesignTokens.swift) | Colors, fonts, spacing, radius, motion |
| [Icons.swift](Icons.swift) | `PenovaIcon` enum + `PenovaIconView` (prefers SF Symbols, falls back to bundled SVG) |
| [Models.swift](Models.swift) | SwiftData-ready data models (User, Subscription, Project, Episode, Scene, etc.) |
| [FreemiumLimits.swift](FreemiumLimits.swift) | `FreemiumCheck`, `Limits`, `PaywallSource` |
| [Copy.swift](Copy.swift) | All user-facing strings |
| [Components.swift](Components.swift) | `PenovaButton`, `PenovaTag`, `PenovaChip`, `CuePill`, `ProjectCard`, `SceneItem`, `CharacterCard`, `EmptyState`, `PenovaFAB`, `PenovaTextField`, `PenovaSectionHeader` |

### Assets
- [icons/](icons/) — 24 SVG icons using `currentColor` so SwiftUI can tint via `.foregroundStyle`

### Spec
| Doc | Read when… |
|---|---|
| [spec/SwiftUIMapping.md](spec/SwiftUIMapping.md) | You need the Apple primitive for any spec concept |
| [spec/NavigationGraph.md](spec/NavigationGraph.md) | You need the flow between the 21 screens |
| [spec/PerScreenSpec.md](spec/PerScreenSpec.md) | You're implementing a specific screen (S01–S22) |
| [spec/BuildOrder.md](spec/BuildOrder.md) | You're deciding what to build next |

## Design system at a glance

- **Theme**: dark only (MVP)
- **Palette**: ink / snow / amber (primary) / jade (success) / ember (error) / slate (info) / paper (surfaces)
- **Typography**: Inter (UI), Roboto Mono (script content)
- **Spacing**: 4 / 8 / 12 / 16 / 24 / 40 / 64
- **Radius**: 8 (sm), 12 (md), ∞ (full / capsule)
- **Motion**: 120 / 200 / 320 ms, cubic-bezier `(0.2, 0.8, 0.2, 1)`

## Freemium

- **Free**: 1 project, 15 scenes, PDF export only
- **Pro**: unlimited projects & scenes, FDX export

## Bootstrap checklist

1. Create an iOS 17+ SwiftUI app.
2. Drop `PenovaSpec/` into the project (keep the folder).
3. Register Inter + Roboto Mono in `Info.plist` via `UIAppFonts`.
4. Add SVGs from `icons/` to the asset catalog as **Single Scale Vector** + **Preserve Vector Data** + **Template Image** render mode (name them to match `PenovaIcon.rawValue`).
5. Configure `ModelContainer` for SwiftData with the types from `Models.swift`.
6. Force `.preferredColorScheme(.dark)` on the root `WindowGroup`.
7. Follow [`spec/BuildOrder.md`](spec/BuildOrder.md) milestone-by-milestone.

## Source of truth

- Figma: https://www.figma.com/design/bdPZlVwCRvNrVbVQgzqPFv/Penova-iOS-App-Design
- PDF: `Penova — iOS App Design.pdf` (in the repo root)
