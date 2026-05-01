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
                    onBackspaceOnEmpty: { delete(el) }
                )
                .id(el.id)
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
        .onAppear {
            if let last = scene.elementsOrdered.last {
                focused = last.id
            }
        }
        .onChange(of: scene.id) { _, _ in
            if let last = scene.elementsOrdered.last {
                focused = last.id
            }
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
        scene.updatedAt = .now
        try? context.save()
    }

    private func cycleKind(for el: SceneElement) {
        el.kind = EditorLogic.tabCycle(from: el.kind)
        scene.updatedAt = .now
        try? context.save()
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
}

// MARK: - Editable row (pure SwiftUI)

private struct EditableElementRow: View {
    @Bindable var element: SceneElement
    @FocusState.Binding var focusedID: String?
    let onCommit: () -> Void
    let onTab: () -> Void
    let onReturn: () -> Void
    let onBackspaceOnEmpty: () -> Void

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
