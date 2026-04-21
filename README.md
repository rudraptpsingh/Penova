# Penova

**Write the page. Hide the app.**

A dark-first, offline-first screenplay editor built for Indian screenwriters
on the phone. INT/EXT scenes, clean mono dialogue, one-tap industry-format
PDF. No accounts required.

---

## Stack

- SwiftUI + SwiftData (iOS 17+)
- Generated Xcode project via [xcodegen](https://github.com/yonaskolb/XcodeGen)
- Dark-only UI, portrait-only on iPhone, rotates on iPad

## Build

```sh
brew install xcodegen                # once
xcodegen                             # regenerate Penova.xcodeproj
open Penova.xcodeproj
```

Or from the CLI:

```sh
xcodebuild -project Penova.xcodeproj -scheme Penova \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

## Project layout

```
Penova/
├── App/              # App entry, root flow, seed data
├── Features/         # Screen-level SwiftUI views (Home, Scene, Voice, …)
└── Resources/        # Assets.xcassets, Fonts, PrivacyInfo.xcprivacy
PenovaSpec/           # Design tokens, icons, models, copy — pure Swift, no UI
project.yml           # xcodegen source of truth — never hand-edit .pbxproj
```

## Shipping

See [RELEASE.md](RELEASE.md) for the archive → TestFlight → App Store playbook.

Every deferred feature (FDX export, StoreKit 2, sync) is tracked as a
`// STUB:` comment in code and listed in [STUBS.md](STUBS.md).

## License

Proprietary. See [LICENSE](LICENSE). Bundled fonts retain their original
open-font licenses (see `Penova/Resources/Fonts/*.txt`).
