//
//  ScriptEditorPane.swift
//  Penova for Mac
//
//  The cream-paper script editor. Renders SceneElements in proper
//  screenplay format (Roboto Mono, WGA-style column indents) on the
//  paper surface that's the iOS app's signature look — adapted for
//  Mac with full inline editing, Tab to cycle element kind, Return to
//  advance to a new row of the contextually-correct kind.
//

import SwiftUI
import SwiftData
import AppKit
import PenovaKit

struct ScriptEditorPane: View {
    let scene: ScriptScene?
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 0) {
                if let scene {
                    PaperPage(scene: scene)
                        .padding(.vertical, 40)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(PenovaColor.ink0)
        .accessibilityIdentifier(A11yID.editorPane)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(PenovaColor.snow4)
            Text("Select a scene to edit")
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow3)
            Text("Pick one from the sidebar — or press ⌘⇧N for a new scene.")
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow4)
        }
        .padding(64)
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

// MARK: - Paper page

struct PaperPage: View {
    @Bindable var scene: ScriptScene
    @Environment(\.modelContext) private var context
    @FocusState private var focused: String?
    /// Pending paste awaiting user confirmation. Populated when ⇧⌘V is
    /// pressed and the detector returns `.maybeScreenplay`. The pill
    /// overlays above the editor; tapping Convert/Keep dismisses it.
    @State private var pendingPaste: PendingPaste?

    /// Stashed payload for the smart-paste flow. Holds the raw string
    /// + verdict + the anchor element that was focused at the moment
    /// of the paste so we can insert at the right spot once the user
    /// decides what to do.
    private struct PendingPaste: Identifiable {
        let id = UUID()
        let text: String
        let verdict: ScreenplayPasteVerdict
        let anchorID: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Page number top-right
            HStack {
                Spacer()
                Text("1.")
                    .font(.custom("RobotoMono-Medium", size: 12))
                    .foregroundStyle(paperInk.opacity(0.45))
            }
            .padding(.bottom, 24)

            // Scene heading (read-only here; editable from inspector)
            Text(scene.heading)
                .font(.custom("RobotoMono-Medium", size: 14))
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(paperInk)
                .padding(.bottom, 12)

            // Element rows
            ForEach(scene.elementsOrdered) { el in
                EditableElementRow(
                    element: el,
                    focusedID: $focused,
                    onCommit: { commit(el) },
                    onTab: { cycleKind(for: el) },
                    onReturn: { appendAfter(el) },
                    onBackspaceOnEmpty: { delete(el) },
                    onDeleteRow: { delete(el) },
                    onInsertAbove: { insertAbove(el, kind: el.kind) }
                )
                .id(el.id)
                .contextMenu {
                    elementRowContextMenu(for: el)
                }
            }

            // Add-row hint
            addRowButton
                .padding(.top, 12)
        }
        .padding(.horizontal, 80)
        .padding(.top, 48)
        .padding(.bottom, 80)
        .frame(width: 640, alignment: .leading)
        .background(PenovaColor.paper)
        .foregroundStyle(paperInk)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(PenovaColor.paperLine, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 20)
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 4)
        .overlay(alignment: .top) {
            if let pending = pendingPaste {
                PastePromptPill(
                    onConvert: {
                        applyConversion(pending)
                        pendingPaste = nil
                    },
                    onKeepPlain: {
                        applyPlain(pending)
                        pendingPaste = nil
                    }
                )
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            if let last = scene.elementsOrdered.last {
                focused = last.id
            }
        }
        .onChange(of: scene.id) { _, _ in
            if let last = scene.elementsOrdered.last {
                focused = last.id
            }
            pendingPaste = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .penovaSmartPaste)) { _ in
            handleSmartPaste()
        }
    }

    private var paperInk: Color { Color(red: 0.10, green: 0.08, blue: 0.05) }

    private var addRowButton: some View {
        Button(action: { appendAfter(scene.elementsOrdered.last) }) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Add line")
            }
            .font(.custom("RobotoMono-Medium", size: 11))
            .foregroundStyle(paperInk.opacity(0.5))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(paperInk.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Editor actions

    private func commit(_ el: SceneElement) {
        let normalised = EditorLogic.normalise(text: el.text, kind: el.kind)
        if normalised != el.text {
            el.text = normalised
        }
        stampRevision(on: el)
        scene.updatedAt = .now
        try? context.save()
    }

    private func cycleKind(for el: SceneElement) {
        el.kind = EditorLogic.tabCycle(from: el.kind)
        stampRevision(on: el)
        scene.updatedAt = .now
        try? context.save()
    }

    /// Stamp the active revision id on `el` if the project currently
    /// has a revision in flight. Drives the per-element "starred"
    /// markers in the right margin of revision PDF pages.
    private func stampRevision(on el: SceneElement) {
        guard let rev = scene.episode?.project?.activeRevision else { return }
        el.lastRevisedRevisionID = rev.id
    }

    private func appendAfter(_ anchor: SceneElement?) {
        if let anchor { commit(anchor) }
        let nextKind: SceneElementKind = anchor.map { EditorLogic.nextKind(after: $0.kind) } ?? .heading
        let newOrder = (scene.elements.map(\.order).max() ?? -1) + 1
        let newEl = SceneElement(kind: nextKind, text: "", order: newOrder)
        newEl.scene = scene
        if nextKind == .dialogue,
           let lastChar = scene.elementsOrdered.last(where: { $0.kind == .character })?.text {
            newEl.characterName = lastChar
        }
        stampRevision(on: newEl)
        context.insert(newEl)
        scene.updatedAt = .now
        try? context.save()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.focused = newEl.id
        }
    }

    private func delete(_ el: SceneElement) {
        let prev = scene.elementsOrdered.last { $0.order < el.order }
        context.delete(el)
        scene.updatedAt = .now
        try? context.save()
        focused = prev?.id
    }

    /// Insert a new element of the given kind directly above `anchor`.
    /// Inserted row gets focus.
    private func insertAbove(_ anchor: SceneElement, kind: SceneElementKind = .action) {
        let target = anchor.order
        // Shift existing siblings ≥ target up by 1 to make room.
        for el in scene.elementsOrdered where el.order >= target {
            el.order += 1
        }
        let newEl = SceneElement(kind: kind, text: "", order: target)
        newEl.scene = scene
        stampRevision(on: newEl)
        context.insert(newEl)
        scene.updatedAt = .now
        try? context.save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.focused = newEl.id
        }
    }

    /// Right-click context menu surfaced from each element row. Mirrors
    /// Final Draft's standard Insert / Change Kind / Delete actions —
    /// users discover these features via right-click rather than having
    /// to memorise hidden keyboard shortcuts.
    @ViewBuilder
    private func elementRowContextMenu(for el: SceneElement) -> some View {
        Button("Insert line above") {
            insertAbove(el, kind: el.kind)
        }
        Button("Insert line below") {
            appendAfter(el)
        }
        Menu("Change kind") {
            ForEach(SceneElementKind.allCases, id: \.self) { k in
                Button(action: { changeKind(of: el, to: k) }) {
                    HStack {
                        Text(k.display)
                        if el.kind == k {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        Divider()
        Button("Delete line", role: .destructive) {
            delete(el)
        }
    }

    private func changeKind(of el: SceneElement, to kind: SceneElementKind) {
        el.kind = kind
        stampRevision(on: el)
        scene.updatedAt = .now
        try? context.save()
    }

    // MARK: - F4 smart paste

    /// Read NSPasteboard, classify, route. Direct-Fountain skips the
    /// pill and inserts immediately. .maybeScreenplay shows the pill
    /// for the user to confirm. .plain inserts a single Action.
    private func handleSmartPaste() {
        guard let raw = NSPasteboard.general.string(forType: .string),
              !raw.isEmpty else { return }
        let verdict = ScreenplayPasteDetector.classify(raw)
        let anchorID = focused
        switch verdict {
        case .fountain:
            insertBlocks(
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
            insertBlocks(
                ScreenplayPasteConverter.convert(raw, verdict: verdict),
                afterID: anchorID
            )
        }
    }

    /// User tapped "Convert" on the pill — parse via the lite parser
    /// and insert the typed blocks.
    private func applyConversion(_ p: PendingPaste) {
        let blocks = ScreenplayPasteConverter.convert(p.text, verdict: p.verdict)
        insertBlocks(blocks, afterID: p.anchorID)
    }

    /// User tapped "Keep as plain text" or the pill auto-dismissed —
    /// fall back to a single Action element.
    private func applyPlain(_ p: PendingPaste) {
        let blocks = ScreenplayPasteConverter.convert(p.text, verdict: .plain)
        insertBlocks(blocks, afterID: p.anchorID)
    }

    /// Insert the given typed blocks as new SceneElements, slotted in
    /// after the element with `afterID` (or at the end if no anchor).
    /// All inserts land in a single `context.save()` so undo restores
    /// the pre-paste state in one step.
    private func insertBlocks(
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

        // Shift everyone after the anchor up by `blocks.count` so the
        // inserted run slots in contiguously.
        for el in scene.elementsOrdered where el.order > anchorOrder {
            el.order += blocks.count
        }

        var nextOrder = anchorOrder + 1
        var firstInsertedID: String?
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
            if firstInsertedID == nil { firstInsertedID = new.id }
            nextOrder += 1
        }
        scene.updatedAt = .now
        try? context.save()

        if let id = firstInsertedID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.focused = id
            }
        }
    }
}

// MARK: - Editable row (pure SwiftUI)

private struct EditableElementRow: View {
    @Bindable var element: SceneElement
    @FocusState.Binding var focusedID: String?
    @Environment(\.modelContext) private var context
    let onCommit: () -> Void
    let onTab: () -> Void
    let onReturn: () -> Void
    let onBackspaceOnEmpty: () -> Void
    /// ⌘⌫ — delete this row regardless of whether its text is empty.
    var onDeleteRow: () -> Void = {}
    /// ⇧⌘I — insert a new row directly above this one.
    var onInsertAbove: () -> Void = {}

    private let pageWidth: CGFloat = 480 // 640 - 80*2

    var body: some View {
        let isFocused = focusedID == element.id
        HStack(spacing: 0) {
            if element.kind == .transition { Spacer(minLength: 0) }

            ZStack(alignment: .leading) {
                if element.text.isEmpty && !isFocused {
                    Text(placeholder)
                        .font(.custom("RobotoMono-Medium", size: 14))
                        .foregroundStyle(paperInk.opacity(0.32))
                        .italic(element.kind == .parenthetical)
                        .textCase(isUpper ? .uppercase : nil)
                        .allowsHitTesting(false)
                }

                TextField("", text: $element.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.custom("RobotoMono-Medium", size: 14))
                    .fontWeight(element.kind == .heading ? .semibold : .medium)
                    .italic(element.kind == .parenthetical)
                    .textCase(isUpper ? .uppercase : nil)
                    .foregroundStyle(paperInk)
                    .multilineTextAlignment(element.kind == .transition ? .trailing : .leading)
                    .focused($focusedID, equals: element.id)
                    .lineLimit(1...10)
                    .onSubmit(onCommit)
                    .onKeyPress(.tab) {
                        onTab()
                        return .handled
                    }
                    .onKeyPress(.return) {
                        onCommit()
                        onReturn()
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        if element.text.isEmpty {
                            onBackspaceOnEmpty()
                            return .handled
                        }
                        return .ignored
                    }
                    .onChange(of: focusedID) { _, new in
                        // Commit when this row loses focus
                        if new != element.id {
                            onCommit()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .penovaSetElementKind)) { note in
                        // ⌘1–⌘7 — only the focused row reacts.
                        guard focusedID == element.id,
                              let raw = note.userInfo?["kind"] as? String,
                              let kind = SceneElementKind(rawValue: raw)
                        else { return }
                        element.kind = kind
                        if let rev = element.scene?.episode?.project?.activeRevision {
                            element.lastRevisedRevisionID = rev.id
                        }
                        element.scene?.updatedAt = .now
                        try? context.save()
                        PenovaLog.editor.info("⌘-shortcut set kind: \(raw, privacy: .public)")
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .penovaDeleteFocusedElement)) { _ in
                        // ⌘⌫ deletes the focused row outright (Final
                        // Draft convention). Empty-row backspace is
                        // handled separately in `.onKeyPress(.delete)`.
                        guard focusedID == element.id else { return }
                        onDeleteRow()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .penovaInsertLineAbove)) { _ in
                        guard focusedID == element.id else { return }
                        onInsertAbove()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .penovaInsertLineBelow)) { _ in
                        guard focusedID == element.id else { return }
                        onReturn()
                    }
            }
            .padding(.leading, leadingIndent)
            .padding(.trailing, trailingIndent)
            .padding(.vertical, paddingV)
            .frame(maxWidth: pageWidth - leadingIndent - trailingIndent,
                   alignment: element.kind == .transition ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if isFocused {
                kindBadge
                    .offset(x: 8, y: -2)
            }
        }
    }

    private var paperInk: Color { Color(red: 0.10, green: 0.08, blue: 0.05) }

    private var kindBadge: some View {
        Text(element.kind.display)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(paperInk.opacity(0.6))
            .textCase(.uppercase)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(paperInk.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var placeholder: String {
        switch element.kind {
        case .heading:       return "INT. LOCATION — TIME"
        case .action:        return "What happens. (Action.)"
        case .character:     return "CHARACTER"
        case .dialogue:      return "What they say."
        case .parenthetical: return "(parenthetical)"
        case .transition:    return "CUT TO:"
        case .actBreak:      return "END OF ACT"
        }
    }

    private var isUpper: Bool {
        [SceneElementKind.heading, .character, .transition, .actBreak].contains(element.kind)
    }

    private var paddingV: CGFloat {
        switch element.kind {
        case .heading, .action, .actBreak, .transition: return 6
        case .character: return 4
        case .dialogue, .parenthetical: return 0
        }
    }

    private var leadingIndent: CGFloat {
        switch element.kind {
        case .heading, .action, .actBreak: return 0
        case .character:                   return pageWidth * 0.36
        case .parenthetical:               return pageWidth * 0.28
        case .dialogue:                    return pageWidth * 0.18
        case .transition:                  return 0
        }
    }

    private var trailingIndent: CGFloat {
        element.kind == .dialogue ? pageWidth * 0.16 : 0
    }
}
