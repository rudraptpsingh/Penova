//
//  ElementTypeSheet.swift
//  Penova
//
//  S12 — Picker for which SceneElement kind to add next. Full kind set
//  rendered as big tappable tiles so one-thumb selection is painless.
//

import SwiftUI

struct ElementTypeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (SceneElementKind) -> Void

    private let kinds: [SceneElementKind] = [
        .action, .character, .dialogue, .parenthetical, .transition, .heading, .actBreak
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.s) {
                    Text("Add element")
                        .font(PenovaFont.labelCaps)
                        .tracking(PenovaTracking.labelCaps)
                        .foregroundStyle(PenovaColor.snow3)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: PenovaSpace.s) {
                        ForEach(kinds, id: \.rawValue) { kind in
                            Button {
                                onPick(kind)
                            } label: {
                                tile(for: kind)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("Element type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(for kind: SceneElementKind) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            PenovaIconView(icon(for: kind), size: 22, color: PenovaColor.amber)
            Text(kind.display)
                .font(PenovaFont.bodyLarge)
                .foregroundStyle(PenovaColor.snow)
            Text(hint(for: kind))
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow3)
                .lineLimit(2)
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    private func icon(for kind: SceneElementKind) -> PenovaIcon {
        switch kind {
        case .heading:       return .scenes
        case .action:        return .action
        case .character:     return .characters
        case .dialogue:      return .dialogue
        case .parenthetical: return .parens
        case .transition:    return .transition
        case .actBreak:      return .scenes
        }
    }

    private func hint(for kind: SceneElementKind) -> String {
        switch kind {
        case .heading:       return "A new slug line."
        case .action:        return "What the camera sees."
        case .character:     return "Who speaks next."
        case .dialogue:      return "What they say."
        case .parenthetical: return "How they say it."
        case .transition:    return "CUT TO, FADE OUT."
        case .actBreak:      return "END OF ACT ONE."
        }
    }
}
