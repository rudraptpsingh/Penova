//
//  SceneDetailScreen.swift
//  Penova
//
//  S10 — Scene detail. Renders the heading + description + every
//  SceneElement in its screenplay-formatted shape (mono, with correct
//  indent/alignment per kind). FAB appends a blank Action element and
//  pushes straight into the editor (Task 8).
//

import SwiftUI
import SwiftData

struct SceneDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Bindable var scene: ScriptScene

    @State private var pendingEdit: SceneElement?
    @State private var showElementType = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    heading
                    if scene.elements.isEmpty {
                        EmptyState(
                            icon: .action,
                            title: "Write the page.",
                            message: "Hide the app. Tap + to add your first element.",
                            ctaTitle: "Add element",
                            ctaAction: { showElementType = true }
                        )
                    } else {
                        VStack(alignment: .leading, spacing: PenovaSpace.s) {
                            ForEach(scene.elementsOrdered) { el in
                                SceneElementRow(element: el)
                                    .contentShape(Rectangle())
                                    .onTapGesture { pendingEdit = el }
                            }
                        }
                    }
                }
                .padding(PenovaSpace.l)
                .padding(.bottom, PenovaSpace.xxl)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        scene.bookmarked.toggle()
                        try? context.save()
                    } label: {
                        PenovaIconView(.bookmark, size: 18,
                                       color: scene.bookmarked ? PenovaColor.amber : PenovaColor.snow3)
                    }
                }
            }

            if !scene.elements.isEmpty {
                PenovaFAB(icon: .plus) { showElementType = true }
                    .padding(PenovaSpace.l)
            }
        }
        .sheet(isPresented: $showElementType) {
            ElementTypeSheet { kind in
                showElementType = false
                let el = appendElement(kind: kind)
                pendingEdit = el
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingEdit) { el in
            SceneElementEditor(element: el) { next in
                pendingEdit = next
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

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

    private func appendElement(kind: SceneElementKind) -> SceneElement {
        let nextOrder = (scene.elements.map(\.order).max() ?? -1) + 1
        let placeholder: String
        switch kind {
        case .heading:       placeholder = ""
        case .action:        placeholder = ""
        case .character:     placeholder = ""
        case .dialogue:      placeholder = ""
        case .parenthetical: placeholder = ""
        case .transition:    placeholder = "CUT TO:"
        }
        let el = SceneElement(kind: kind, text: placeholder, order: nextOrder)
        el.scene = scene
        context.insert(el)
        scene.updatedAt = .now
        try? context.save()
        return el
    }
}

// MARK: - Element row (read-only rendering)
//
// Industry ladder — widths expressed as fractions of the 6" action block
// (action 0pt / 432pt wide, character 158pt in, parens 116pt in with 144pt
// width, dialogue 72pt in with 252pt width, transition right-aligned).

private struct ElementRowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SceneElementRow: View {
    let element: SceneElement

    @State private var width: CGFloat = 0

    // Fractions of the action block (432pt = 6"). Mirror the PDF ladder so
    // on-screen rendering matches the printed page.
    private enum Ladder {
        static let characterIndent: CGFloat = 158.0 / 432.0
        static let parensIndent:    CGFloat = 116.0 / 432.0
        static let parensWidth:     CGFloat = 144.0 / 432.0
        static let dialogueIndent:  CGFloat =  72.0 / 432.0
        static let dialogueWidth:   CGFloat = 252.0 / 432.0
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ElementRowWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(ElementRowWidthKey.self) { width = $0 }
            .padding(.vertical, PenovaSpace.xs)
    }

    @ViewBuilder
    private var content: some View {
        switch element.kind {
        case .heading:
            Text(element.text.uppercased())
                .font(PenovaFont.monoScript)
                .foregroundStyle(PenovaColor.snow)

        case .action:
            Text(element.text.isEmpty ? "Action…" : element.text)
                .font(PenovaFont.monoScript)
                .foregroundStyle(element.text.isEmpty ? PenovaColor.snow4 : PenovaColor.snow)

        case .character:
            Text(element.text.uppercased())
                .font(PenovaFont.monoScript)
                .foregroundStyle(PenovaColor.snow)
                .padding(.leading, width * Ladder.characterIndent)

        case .dialogue:
            Text(element.text.isEmpty ? "Dialogue…" : element.text)
                .font(PenovaFont.monoScript)
                .foregroundStyle(element.text.isEmpty ? PenovaColor.snow4 : PenovaColor.snow)
                .frame(width: max(0, width * Ladder.dialogueWidth), alignment: .leading)
                .padding(.leading, width * Ladder.dialogueIndent)

        case .parenthetical:
            Text("(\(element.text))")
                .font(PenovaFont.monoScript)
                .foregroundStyle(PenovaColor.snow3)
                .frame(width: max(0, width * Ladder.parensWidth), alignment: .leading)
                .padding(.leading, width * Ladder.parensIndent)

        case .transition:
            Text(element.text.uppercased())
                .font(PenovaFont.monoScript)
                .foregroundStyle(PenovaColor.snow)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
