# Per-Screen Spec — Penova v0.1

Compact layout + behaviour reference for each of the 21 screens. Use with `SwiftUIMapping.md` for primitive selection.

Spacing token legend: `xs=4 s=8 sm=12 m=16 l=24 xl=40 xxl=64`.

---

## S01 Splash
- **Layout**: Centred `Penova` wordmark in `PenovaFont.hero` on ink bg.
- **Behaviour**: 320 ms fade → route to S02 (first launch) or S04 (auth'd) or S03 (signed out).
- **Primitives**: `ZStack` + `.transition(.opacity)`.

## S02 Onboarding
- **Layout**: 3 pages — hero title, body, paging dots, Next button. Skip top-right.
- **Primitives**: `TabView(.page)`, `Button` bottom-pinned.
- **Copy**: `Copy.onboarding.*`.

## S03 Sign-in
- **Layout**: Wordmark top, tagline below, `SignInWithAppleButton` bottom, T&Cs micro text.
- **Primitives**: `SignInWithAppleButton(.signIn, onRequest:, onCompletion:)` with `.signInWithAppleButtonStyle(.white)`.

## S04 Home
- **Layout**: Scrollview with: greeting (`Copy.home.greeting(forHour:)`) → "Recent scripts" header → `LazyVStack` of `ProjectCard`s → FAB bottom-right.
- **Padding**: horizontal `l` (24), vertical `m` (16) between cards `sm` (12).
- **Behaviour**: Pull-to-refresh reloads from SwiftData. FAB → S06 (new project).
- **Primitives**: `ScrollView` + `.refreshable`, `.searchable` prompt "Search projects".
- **Empty state**: `Copy.emptyStates.noProjects`.

## S05 Project Detail
- **Layout**: Back + title + More menu → project meta (genre tag, episode count) → "Episodes" section → scrolling list → "New Episode" ghost button.
- **Primitives**: `NavigationStack` push; `Menu { ... } label: { Image(systemName: "ellipsis") }`.

## S06 New Project (sheet)
- **Layout**: Drag indicator → "New Project" title → Name `TextField`, Genre `Picker`, Description `TextEditor` → Create button.
- **Detent**: `.medium`.
- **Freemium check**: `FreemiumCheck.canCreateProject` before save.

## S07 Episodes List (push)
- **Layout**: List of rows (title, scene count, last edited). Swipe → Delete / Rename.
- **Primitives**: `List` `.swipeActions`.

## S08 Scene List (push)
- **Layout**: Beat badge + location + time-of-day + snippet. Swipe → Delete, Bookmark.
- **Behaviour**: Tap → S10. Long-press → reorder (`.onMove`).

## S09 New Scene (sheet)
- **Layout**: Location `TextField`, Time of Day `Picker`, Beat Type `Picker`, Create.
- **Detent**: `.medium`.

## S10 Scene Detail
- **Layout**: Header (location, time, beat tag) → list of `SceneElement` rows typed by kind → "Open Editor" CTA.
- **Primitives**: Custom `VStack` with typed element rendering; Action = bodyLarge, Dialogue = centred mono, Parens = italic smaller.

## S11 Editor (push, full screen)
- **Layout**: Custom top bar (back, scene title, More) → large `TextEditor` mono 13pt → keyboard accessory row (Action / Dialogue / Parens / Transition).
- **Behaviour**: Autosave debounced 500 ms. Tap accessory → S12 sheet for type switch OR inline transform.
- **Primitives**: `.toolbar(.hidden, for: .tabBar)`, custom `.safeAreaInset(edge: .bottom)` for keyboard toolbar.

## S12 Element Type Sheet
- **Layout**: 4-up grid of element types with icons (Action / Dialogue / Parens / Transition).
- **Detent**: `.fraction(0.35)`.
- **Primitives**: `LazyVGrid` columns: 2.

## S14 Characters (tab root)
- **Layout**: 2-col `LazyVGrid` of `CharacterCard`s; FAB → new character sheet.
- **Padding**: `l` horizontal, `sm` between cards.

## S15 Character Detail (push)
- **Layout**: Hero card (name, role tag, age) → sections (Bio, Arc, Notes) → appears-in scenes list.
- **Edit**: Inline edit or ellipsis → edit sheet.

## S16 Scenes (tab root)
- **Layout**: All scenes across projects; group by project header.
- **Primitives**: `List` sectioned; header = `Copy.common` project name.

## S17 Scene Search (tab deep)
- **Layout**: Search bar → filter chip row (Beat / Location / Time of Day / Bookmarked) → results.
- **Primitives**: `.searchable(text:)` + `ScrollView(.horizontal)` chips.

## S18 Settings (push)
- **Layout**: Grouped list: Account (name, email, sign out), Subscription (plan + manage), About (version, privacy, terms).
- **Primitives**: `List` `.listStyle(.insetGrouped)`.

## S19 Quick Capture (sheet, global)
- **Layout**: Big mic button centred → waveform → live transcript → "Save to Inbox" + Discard.
- **Detent**: `.large`.
- **Primitives**: `Speech` + `AVAudioEngine`; pulsing circle via `.scaleEffect` animated with `PenovaMotion.slow`.
- **Access**: Triggered from FAB long-press or shake gesture.

## S20 Paywall (sheet)
- **Layout**: Hero title (source-aware via `PaywallSource`), features list (checkmarks), plan toggle (monthly / annual), CTA button, Restore link.
- **Detent**: `.large`.
- **Primitives**: StoreKit `Product.products(for:)`, `.sensoryFeedback(.success, trigger:)` on purchase.

## S21 Delete Confirm
- **Primitive**: `.confirmationDialog("Delete X?", isPresented:)` with `.destructive` button + Cancel.
- **Copy**: `Copy.deleteConfirm.*`.

## S22 Limit Reached (sheet)
- **Layout**: Icon → heading ("You've reached X") → body → "Upgrade to Pro" primary + "Not now" ghost.
- **Detent**: `.medium`.
- **Behaviour**: CTA pushes S20.

---

## Shared components used across screens

| Component | Screens |
|---|---|
| `ProjectCard` | S04, S05 header |
| `ScriptItem` | S07 |
| `SceneItem` | S08, S10, S16, S17 |
| `CharacterCard` | S14, S15 ref list |
| `PenovaTag` | S05, S08, S10, S15 |
| `EmptyState` | S04, S07, S08, S14, S16, S19 inbox |
