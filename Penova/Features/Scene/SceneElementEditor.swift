//
//  SceneElementEditor.swift
//  Penova
//
//  S11 — Focused editor for a single SceneElement. Mono font, kind-aware
//  autocapitalisation, character autocomplete for dialogue flow, and a
//  "Save & add next" chip so the writer can keep typing without leaving.
//

import SwiftUI
import SwiftData

struct SceneElementEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var element: SceneElement
    /// Called when the user picks a "Then" chip. Parent swaps the edited
    /// element to the freshly inserted one so the writer keeps typing.
    var onNext: ((SceneElement) -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PenovaSpace.m) {
                Text(element.kind.display.uppercased())
                    .font(PenovaFont.labelCaps)
                    .tracking(PenovaTracking.labelCaps)
                    .foregroundStyle(PenovaColor.amber)

                TextEditor(text: $element.text)
                    .font(PenovaFont.monoScript)
                    .foregroundStyle(PenovaColor.snow)
                    .scrollContentBackground(.hidden)
                    .background(PenovaColor.ink2)
                    .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                    .focused($focused)
                    .textInputAutocapitalization(
                        element.kind == .character || element.kind == .transition ? .characters : .sentences
                    )

                if element.kind == .character {
                    characterSuggestions
                }

                Spacer()

                nextElementChips
            }
            .padding(PenovaSpace.l)
            .background(PenovaColor.ink0)
            .navigationTitle(element.kind.display)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { commitAndDismiss() }
                        .foregroundStyle(PenovaColor.amber)
                        .bold()
                }
            }
            .onAppear { focused = true }
            .onDisappear {
                // Swipe-dismiss still writes the in-flight edit to disk.
                element.scene?.updatedAt = .now
                try? context.save()
            }
        }
    }

    // MARK: Character autocomplete

    private var projectCharacters: [ScriptCharacter] {
        element.scene?.episode?.project?.characters ?? []
    }

    private var characterMatches: [ScriptCharacter] {
        let query = element.text.trimmingCharacters(in: .whitespaces).uppercased()
        if query.isEmpty { return projectCharacters }
        return projectCharacters.filter { $0.name.uppercased().contains(query) }
    }

    @ViewBuilder
    private var characterSuggestions: some View {
        if !characterMatches.isEmpty {
            VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                Text("Suggestions")
                    .font(PenovaFont.labelCaps)
                    .tracking(PenovaTracking.labelCaps)
                    .foregroundStyle(PenovaColor.snow4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PenovaSpace.s) {
                        ForEach(characterMatches.prefix(8)) { ch in
                            Button {
                                element.text = ch.name.uppercased()
                            } label: {
                                Text(ch.name.uppercased())
                                    .font(PenovaFont.monoScript)
                                    .foregroundStyle(PenovaColor.snow)
                                    .padding(.horizontal, PenovaSpace.sm)
                                    .padding(.vertical, PenovaSpace.s)
                                    .background(PenovaColor.ink3)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: "Save & add next" chips

    private var suggestedNext: [SceneElementKind] {
        switch element.kind {
        case .heading:       return [.action]
        case .action:        return [.character, .action]
        case .character:     return [.dialogue, .parenthetical]
        case .parenthetical: return [.dialogue]
        case .dialogue:      return [.action, .character]
        case .transition:    return [.heading]
        }
    }

    private var nextElementChips: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text("Then")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow4)
            HStack(spacing: PenovaSpace.s) {
                ForEach(suggestedNext, id: \.rawValue) { kind in
                    PenovaChip(text: kind.display, isSelected: false) {
                        commitAndInsert(kind)
                    }
                }
            }
        }
    }

    // MARK: Commit

    private func commitAndDismiss() {
        try? context.save()
        dismiss()
    }

    private func commitAndInsert(_ kind: SceneElementKind) {
        try? context.save()
        guard let scene = element.scene else {
            dismiss()
            return
        }
        let nextOrder = (scene.elements.map(\.order).max() ?? -1) + 1
        let new = SceneElement(kind: kind, text: "", order: nextOrder)
        new.scene = scene
        context.insert(new)
        scene.updatedAt = .now
        try? context.save()
        if let onNext {
            onNext(new)
        } else {
            dismiss()
        }
    }
}
