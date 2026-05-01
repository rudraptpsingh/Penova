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
import PenovaKit

struct SceneDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var scene: ScriptScene

    @FocusState private var focused: String?
    @State private var showEditScene = false
    @State private var showDeleteConfirm = false
    /// F4 — pending smart paste awaiting user confirmation. The pill
    /// overlays above the editor; tapping Convert / Keep / auto-
    /// dismiss resolves it.
    @State private var pendingPaste: PendingPaste?

    private struct PendingPaste: Identifiable {
        let id = UUID()
        let text: String
        let verdict: ScreenplayPasteVerdict
        let anchorID: String?
    }

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
                                cuePool: cuePool,
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
            .overlay(alignment: .top) {
                if let pending = pendingPaste {
                    PastePromptPill(
                        onConvert: {
                            applySmartPaste(pending, asPlain: false)
                            pendingPaste = nil
                        },
                        onKeepPlain: {
                            applySmartPaste(pending, asPlain: true)
                            pendingPaste = nil
                        }
                    )
                    .padding(.horizontal, PenovaSpace.m)
                    .padding(.top, PenovaSpace.s)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
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
        .onAppear {
            // Remember this scene as the "last opened" so Home can offer a
            // resume card next launch. Keyed per the stream brief.
            UserDefaults.standard.set(scene.id, forKey: "penova.lastOpenedSceneID")
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
            .accessibilityLabel(scene.bookmarked ? "Remove bookmark" : "Bookmark scene")
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
            .accessibilityLabel("Scene actions")
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

                        Divider()
                            .frame(height: 20)
                            .padding(.horizontal, PenovaSpace.xs)

                        Button {
                            triggerSmartPaste(anchor: el)
                        } label: {
                            HStack(spacing: PenovaSpace.xs) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(PenovaColor.snow)
                                Text("Smart paste")
                                    .font(PenovaFont.bodySmall)
                                    .foregroundStyle(PenovaColor.snow)
                            }
                            .padding(.horizontal, PenovaSpace.s)
                            .padding(.vertical, PenovaSpace.xs)
                        }
                        .accessibilityLabel("Smart paste from clipboard")
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
        case .actBreak:      return "ACT"
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

    /// Frequency-sorted character cue pool for autocomplete: includes
    /// every name typed elsewhere in the project plus any registered
    /// `ScriptCharacter`. Computed lazily via `AutocompleteService` so
    /// SwiftData updates flow through @Bindable.
    private var cuePool: [String] {
        guard let project = scene.episode?.project else {
            return projectCharacters.map { $0.name.uppercased() }
        }
        return AutocompleteService.characterCues(in: project)
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
        stampRevision(on: new)
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
        stampRevision(on: el)
        scene.updatedAt = .now
        try? context.save()
    }

    /// If the project has a revision in flight, stamp `el` so the PDF
    /// renderer flags it on the next revision page render.
    private func stampRevision(on el: SceneElement) {
        guard let rev = scene.episode?.project?.activeRevision else { return }
        el.lastRevisedRevisionID = rev.id
    }

    private func insertAtCursor(_ glyph: String, into el: SceneElement) {
        // We don't have true cursor access through @Bindable/TextField, so
        // we append. For most punctuation this is what the writer wants.
        el.text.append(glyph)
        stampRevision(on: el)
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

    // MARK: - F4 smart paste

    /// Read UIPasteboard, classify, route. Direct-Fountain skips the
    /// pill; .maybeScreenplay shows the pill at the top of the editor;
    /// .plain inserts as a single Action element.
    private func triggerSmartPaste(anchor: SceneElement?) {
        guard let raw = UIPasteboard.general.string, !raw.isEmpty else { return }
        let verdict = ScreenplayPasteDetector.classify(raw)
        let anchorID = anchor?.id ?? focused
        switch verdict {
        case .fountain:
            insertSmartPasteBlocks(
                ScreenplayPasteConverter.convert(raw, verdict: verdict),
                afterID: anchorID
            )
        case .maybeScreenplay:
            withAnimation(PenovaMotion.easingFast) {
                pendingPaste = PendingPaste(
                    text: raw, verdict: verdict, anchorID: anchorID
                )
            }
        case .plain:
            insertSmartPasteBlocks(
                ScreenplayPasteConverter.convert(raw, verdict: verdict),
                afterID: anchorID
            )
        }
    }

    private func applySmartPaste(_ p: PendingPaste, asPlain: Bool) {
        let verdict: ScreenplayPasteVerdict = asPlain ? .plain : p.verdict
        let blocks = ScreenplayPasteConverter.convert(p.text, verdict: verdict)
        insertSmartPasteBlocks(blocks, afterID: p.anchorID)
    }

    private func insertSmartPasteBlocks(
        _ blocks: [ScreenplayPasteConverter.Block],
        afterID: String?
    ) {
        guard !blocks.isEmpty else { return }
        let ordered = scene.elementsOrdered
        let anchorIndex: Int
        if let afterID, let idx = ordered.firstIndex(where: { $0.id == afterID }) {
            anchorIndex = idx
        } else {
            anchorIndex = ordered.count - 1
        }
        let anchorOrder = anchorIndex >= 0 ? ordered[anchorIndex].order : -1

        for el in scene.elementsOrdered where el.order > anchorOrder {
            el.order += blocks.count
        }

        var nextOrder = anchorOrder + 1
        var firstID: String?
        let activeRevID = scene.episode?.project?.activeRevision?.id
        for block in blocks {
            let new = SceneElement(
                kind: block.kind,
                text: block.text,
                order: nextOrder,
                characterName: block.characterName
            )
            new.scene = scene
            if let revID = activeRevID { new.lastRevisedRevisionID = revID }
            context.insert(new)
            scene.elements.append(new)
            if firstID == nil { firstID = new.id }
            nextOrder += 1
        }
        scene.updatedAt = .now
        try? context.save()
        if let id = firstID {
            DispatchQueue.main.async { focused = id }
        }
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
        stampRevision(on: el)
        scene.updatedAt = .now
        try? context.save()
        HabitTracker.record(scene: scene, in: context)
    }

    private func normaliseAndSave() {
        for el in scene.elements {
            if el.kind == .heading || el.kind == .character || el.kind == .transition {
                el.text = el.text.uppercased()
            }
        }
        try? context.save()
        HabitTracker.record(scene: scene, in: context)
    }
}

// MARK: - Inline row

struct SceneElementInlineRow: View {
    @Bindable var element: SceneElement
    /// Pool of distinct character cues for autocomplete: registered
    /// `ScriptCharacter` records + every cue typed elsewhere in the
    /// project (uppercased, frequency-sorted). Strings keep the row
    /// view decoupled from SwiftData.
    let cuePool: [String]
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
        case .actBreak:      return "END OF ACT ONE"
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
        case .actBreak:      return "BREAK"
        }
    }

    // MARK: - Character autocomplete

    private var characterMatches: [String] {
        let query = element.text.trimmingCharacters(in: .whitespaces).uppercased()
        if query.isEmpty { return cuePool }
        return EditorLogic.suggestions(query: query, in: cuePool)
            .filter { $0 != query }   // hide exact-match self
    }

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PenovaSpace.xs) {
                ForEach(characterMatches.prefix(8), id: \.self) { name in
                    Button {
                        element.text = name
                    } label: {
                        Text(name)
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
