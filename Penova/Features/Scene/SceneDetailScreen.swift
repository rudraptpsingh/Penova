//
//  SceneDetailScreen.swift
//  Penova
//
//  S10 — Continuous scene editor. One scrollable view, one row per
//  SceneElement. Return advances to the next element with type
//  inferred from the current row; Tab (external keyboard) and the
//  keyboard accessory bar cycle the current row's kind. Character
//  cues stay uppercased; scene headings auto-uppercase on save.
//

import SwiftUI
import SwiftData

struct SceneDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var scene: ScriptScene

    @FocusState private var focused: String?
    @State private var showEditScene = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PenovaSpace.xs) {
                    heading
                        .padding(.horizontal, PenovaSpace.l)
                        .padding(.top, PenovaSpace.l)

                    if scene.elementsOrdered.isEmpty {
                        EmptyState(
                            icon: .action,
                            title: "Write the page.",
                            message: "Hide the app. Tap below to add your first line.",
                            ctaTitle: "Start writing",
                            ctaAction: { addFirstElement() }
                        )
                        .padding(.horizontal, PenovaSpace.l)
                    } else {
                        ForEach(scene.elementsOrdered) { el in
                            SceneElementInlineRow(
                                element: el,
                                characters: projectCharacters,
                                focused: $focused,
                                onSubmit: { handleReturn(on: el) },
                                onCycleKind: { cycleKind(of: el) },
                                onDelete: { deleteElement(el) }
                            )
                            .id(el.id)
                            .padding(.horizontal, PenovaSpace.l)
                        }

                        // Tap below the last row to append a new Action line.
                        Button {
                            appendBlankAfter(scene.elementsOrdered.last)
                        } label: {
                            HStack(spacing: PenovaSpace.s) {
                                PenovaIconView(.plus, size: 14, color: PenovaColor.snow4)
                                Text("New line")
                                    .font(PenovaFont.bodySmall)
                                    .foregroundStyle(PenovaColor.snow4)
                                Spacer()
                            }
                            .padding(.vertical, PenovaSpace.m)
                            .padding(.horizontal, PenovaSpace.l)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, PenovaSpace.xxl)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbar { keyboardToolbar }
            .onChange(of: focused) { _, newValue in
                if let id = newValue {
                    withAnimation(PenovaMotion.easingFast) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditScene) {
            if let episode = scene.episode {
                NewSceneSheet(episode: episode, editing: scene)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("Delete scene?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteScene() }
        } message: {
            Text("This removes the scene and all of its elements.")
        }
        .onDisappear {
            normaliseAndSave()
        }
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                scene.bookmarked.toggle()
                try? context.save()
            } label: {
                PenovaIconView(.bookmark, size: 18,
                               color: scene.bookmarked ? PenovaColor.amber : PenovaColor.snow3)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showEditScene = true } label: {
                    Label("Edit scene", systemImage: "pencil")
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete scene", systemImage: "trash")
                }
            } label: {
                PenovaIconView(.more, size: 18, color: PenovaColor.snow)
            }
        }
    }

    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            if let id = focused, let el = element(id: id) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PenovaSpace.xs) {
                        // Type chips — tap to switch current row's kind.
                        ForEach(SceneElementKind.allCases, id: \.rawValue) { kind in
                            typeChip(kind: kind, isActive: el.kind == kind) {
                                setKind(kind, on: el)
                            }
                        }

                        Divider()
                            .frame(height: 20)
                            .padding(.horizontal, PenovaSpace.xs)

                        // Quick-insert punctuation.
                        quickInsert("(") { insertAtCursor("(", into: el) }
                        quickInsert(")") { insertAtCursor(")", into: el) }
                        quickInsert("—") { insertAtCursor("—", into: el) }
                        quickInsert("!") { insertAtCursor("!", into: el) }
                        quickInsert("?") { insertAtCursor("?", into: el) }

                        Divider()
                            .frame(height: 20)
                            .padding(.horizontal, PenovaSpace.xs)

                        Button {
                            appendNewScene()
                        } label: {
                            HStack(spacing: PenovaSpace.xs) {
                                PenovaIconView(.scenes, size: 14, color: PenovaColor.amber)
                                Text("New scene")
                                    .font(PenovaFont.bodySmall)
                                    .foregroundStyle(PenovaColor.amber)
                            }
                            .padding(.horizontal, PenovaSpace.s)
                            .padding(.vertical, PenovaSpace.xs)
                        }
                    }
                    .padding(.vertical, PenovaSpace.xs)
                }
            } else {
                Spacer()
                Button("Done") { focused = nil }
                    .foregroundStyle(PenovaColor.amber)
            }
        }
    }

    private func typeChip(kind: SceneElementKind, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(chipLabel(for: kind))
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(isActive ? PenovaColor.ink0 : PenovaColor.snow)
                .padding(.horizontal, PenovaSpace.s)
                .padding(.vertical, PenovaSpace.xs)
                .background(isActive ? PenovaColor.amber : PenovaColor.ink3)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quickInsert(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(PenovaFont.monoScript)
                .foregroundStyle(PenovaColor.snow)
                .frame(minWidth: 28, minHeight: 28)
                .background(PenovaColor.ink3)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(for kind: SceneElementKind) -> String {
        switch kind {
        case .heading:       return "SLUG"
        case .action:        return "ACTION"
        case .character:     return "CHAR"
        case .dialogue:      return "DIAL"
        case .parenthetical: return "PAREN"
        case .transition:    return "TRANS"
        }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            HStack(spacing: PenovaSpace.xs) {
                PenovaTag(text: scene.location.rawValue)
                PenovaTag(text: scene.time.rawValue)
                if let beat = scene.beatType {
                    PenovaTag(
                        text: beat.rawValue.uppercased(),
                        tint: PenovaColor.slate.opacity(0.2),
                        fg: PenovaColor.slate
                    )
                }
            }
            Text(scene.heading)
                .font(PenovaFont.monoScript)
                .foregroundStyle(PenovaColor.snow)
            if let desc = scene.sceneDescription, !desc.isEmpty {
                Text(desc)
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow3)
            }
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    // MARK: - Mutation helpers

    private var projectCharacters: [ScriptCharacter] {
        scene.episode?.project?.characters ?? []
    }

    private func element(id: String) -> SceneElement? {
        scene.elements.first(where: { $0.id == id })
    }

    private func addFirstElement() {
        let el = insertElement(kind: .heading, after: nil)
        el.text = scene.heading
        try? context.save()
        DispatchQueue.main.async { focused = el.id }
    }

    @discardableResult
    private func insertElement(kind: SceneElementKind, after anchor: SceneElement?) -> SceneElement {
        let ordered = scene.elementsOrdered
        let anchorIndex: Int
        if let anchor, let idx = ordered.firstIndex(where: { $0.id == anchor.id }) {
            anchorIndex = idx
        } else {
            anchorIndex = ordered.count - 1
        }

        let new = SceneElement(kind: kind, text: "", order: 0)
        new.scene = scene
        context.insert(new)
        scene.elements.append(new)

        // Re-number everyone after `anchorIndex` so the new element slots in.
        var working = ordered
        working.insert(new, at: anchorIndex + 1)
        for (i, el) in working.enumerated() { el.order = i }
        scene.updatedAt = .now
        try? context.save()
        return new
    }

    private func appendBlankAfter(_ anchor: SceneElement?) {
        let kind: SceneElementKind
        if let anchor {
            kind = nextKind(after: anchor.kind)
        } else {
            kind = .action
        }
        let new = insertElement(kind: kind, after: anchor)
        DispatchQueue.main.async { focused = new.id }
    }

    private func handleReturn(on el: SceneElement) {
        commitNormalisation(for: el)
        // If the element is empty and its kind is Action, treat Return as
        // "demote to Action" escape — but since we default-next is Action,
        // simplest behaviour: always insert the next element.
        let kind = nextKind(after: el.kind)
        let new = insertElement(kind: kind, after: el)
        DispatchQueue.main.async { focused = new.id }
    }

    private func nextKind(after kind: SceneElementKind) -> SceneElementKind {
        EditorLogic.nextKind(after: kind)
    }

    /// Tab / accessory chip cycles the current row's kind.
    private func cycleKind(of el: SceneElement) {
        setKind(EditorLogic.tabCycle(from: el.kind), on: el)
    }

    private func setKind(_ kind: SceneElementKind, on el: SceneElement) {
        guard el.kind != kind else { return }
        el.kind = kind
        if kind == .character || kind == .transition || kind == .heading {
            el.text = el.text.uppercased()
        }
        scene.updatedAt = .now
        try? context.save()
    }

    private func insertAtCursor(_ glyph: String, into el: SceneElement) {
        // We don't have true cursor access through @Bindable/TextField, so
        // we append. For most punctuation this is what the writer wants.
        el.text.append(glyph)
        scene.updatedAt = .now
        try? context.save()
    }

    private func appendNewScene() {
        guard let ep = scene.episode else { return }
        let nextOrder = (ep.scenes.map(\.order).max() ?? -1) + 1
        let new = ScriptScene(locationName: "NEW LOCATION", location: .interior, time: .day, order: nextOrder)
        new.episode = ep
        ep.scenes.append(new)
        context.insert(new)
        ep.updatedAt = .now
        try? context.save()
        focused = nil
    }

    private func deleteElement(_ el: SceneElement) {
        let ordered = scene.elementsOrdered
        let idx = ordered.firstIndex(where: { $0.id == el.id })
        context.delete(el)
        scene.updatedAt = .now
        try? context.save()
        // Focus the prior element if one exists.
        if let idx, idx > 0 {
            focused = ordered[idx - 1].id
        } else if let first = scene.elementsOrdered.first {
            focused = first.id
        } else {
            focused = nil
        }
    }

    private func deleteScene() {
        scene.episode?.updatedAt = .now
        context.delete(scene)
        try? context.save()
        dismiss()
    }

    /// Called just before advancing focus so the current row's text is
    /// normalised (uppercased headings/characters/transitions, trimmed).
    private func commitNormalisation(for el: SceneElement) {
        switch el.kind {
        case .heading, .character, .transition:
            el.text = el.text.uppercased()
        default:
            break
        }
        scene.updatedAt = .now
        try? context.save()
    }

    private func normaliseAndSave() {
        for el in scene.elements {
            if el.kind == .heading || el.kind == .character || el.kind == .transition {
                el.text = el.text.uppercased()
            }
        }
        try? context.save()
    }
}

// MARK: - Inline row

struct SceneElementInlineRow: View {
    @Bindable var element: SceneElement
    let characters: [ScriptCharacter]
    var focused: FocusState<String?>.Binding
    let onSubmit: () -> Void
    let onCycleKind: () -> Void
    let onDelete: () -> Void

    // Ladder — same fractions as the read-only row, applied as leading
    // padding on the typing surface.
    private enum Ladder {
        static let characterIndent: CGFloat = 158.0 / 432.0
        static let parensIndent:    CGFloat = 116.0 / 432.0
        static let dialogueIndent:  CGFloat =  72.0 / 432.0
    }

    @State private var rowWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            HStack(alignment: .top, spacing: PenovaSpace.s) {
                kindBadge
                field
            }
            if element.kind == .character && isFocused && !characterMatches.isEmpty {
                suggestionStrip
            }
        }
        .padding(.vertical, PenovaSpace.xs)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: RowWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(RowWidthKey.self) { rowWidth = $0 }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var isFocused: Bool { focused.wrappedValue == element.id }

    private var kindBadge: some View {
        Text(abbrev(element.kind))
            .font(PenovaFont.labelTiny)
            .tracking(PenovaTracking.labelTiny)
            .foregroundStyle(PenovaColor.snow3)
            .padding(.horizontal, PenovaSpace.xs)
            .padding(.vertical, 2)
            .frame(minWidth: 44, alignment: .center)
            .background(PenovaColor.ink3)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
            .padding(.top, 4)
            .onTapGesture { onCycleKind() }
            .accessibilityLabel("Element kind: \(element.kind.display). Tap to cycle.")
    }

    @ViewBuilder
    private var field: some View {
        let leading = leadingPadding
        TextField(placeholder, text: $element.text, axis: .vertical)
            .font(PenovaFont.monoScript)
            .foregroundStyle(PenovaColor.snow)
            .textInputAutocapitalization(
                element.kind == .character || element.kind == .transition || element.kind == .heading
                    ? .characters : .sentences
            )
            .autocorrectionDisabled(element.kind == .character || element.kind == .transition)
            .submitLabel(.next)
            .focused(focused, equals: element.id)
            .padding(.leading, leading)
            .frame(maxWidth: .infinity, alignment: alignment)
            .onSubmit(onSubmit)
            .onKeyPress(.tab) {
                onCycleKind()
                return .handled
            }
            .onKeyPress(.return) {
                onSubmit()
                return .handled
            }
    }

    private var leadingPadding: CGFloat {
        guard rowWidth > 0 else { return 0 }
        // Account for the badge width + spacing subtracted already — we
        // use remaining row width * ladder fraction.
        let usable = rowWidth - 60 // rough badge + spacing
        switch element.kind {
        case .character:     return usable * Ladder.characterIndent
        case .dialogue:      return usable * Ladder.dialogueIndent
        case .parenthetical: return usable * Ladder.parensIndent
        default:             return 0
        }
    }

    private var alignment: Alignment {
        element.kind == .transition ? .trailing : .leading
    }

    private var placeholder: String {
        switch element.kind {
        case .heading:       return "INT. LOCATION - DAY"
        case .action:        return "Action…"
        case .character:     return "CHARACTER"
        case .dialogue:      return "Dialogue…"
        case .parenthetical: return "parenthetical"
        case .transition:    return "CUT TO:"
        }
    }

    private func abbrev(_ kind: SceneElementKind) -> String {
        switch kind {
        case .heading:       return "SLUG"
        case .action:        return "ACT"
        case .character:     return "CHAR"
        case .dialogue:      return "DIAL"
        case .parenthetical: return "PAREN"
        case .transition:    return "TRANS"
        }
    }

    // MARK: - Character autocomplete (ported from SceneElementEditor)

    private var characterMatches: [ScriptCharacter] {
        let query = element.text.trimmingCharacters(in: .whitespaces).uppercased()
        if query.isEmpty { return characters }
        return characters.filter { $0.name.uppercased().contains(query) }
    }

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PenovaSpace.xs) {
                ForEach(characterMatches.prefix(8)) { ch in
                    Button {
                        element.text = ch.name.uppercased()
                    } label: {
                        Text(ch.name.uppercased())
                            .font(PenovaFont.monoScript)
                            .foregroundStyle(PenovaColor.snow)
                            .padding(.horizontal, PenovaSpace.s)
                            .padding(.vertical, PenovaSpace.xs)
                            .background(PenovaColor.ink3)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 60)
        }
    }
}

private struct RowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
