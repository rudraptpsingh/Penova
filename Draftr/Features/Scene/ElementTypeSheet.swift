//
//  ElementTypeSheet.swift
//  Draftr
//
//  S12 — Picker for which SceneElement kind to add next. Full kind set
//  rendered as big tappable tiles so one-thumb selection is painless.
//

import SwiftUI

struct ElementTypeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (SceneElementKind) -> Void

    private let kinds: [SceneElementKind] = [
        .action, .character, .dialogue, .parenthetical, .transition, .heading
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DraftrSpace.s) {
                    Text("Add element")
                        .font(DraftrFont.labelCaps)
                        .tracking(DraftrTracking.labelCaps)
                        .foregroundStyle(DraftrColor.snow3)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: DraftrSpace.s) {
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
                .padding(DraftrSpace.l)
            }
            .background(DraftrColor.ink0)
            .navigationTitle("Element type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DraftrColor.snow3)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(for kind: SceneElementKind) -> some View {
        VStack(alignment: .leading, spacing: DraftrSpace.s) {
            DraftrIconView(icon(for: kind), size: 22, color: DraftrColor.amber)
            Text(kind.display)
                .font(DraftrFont.bodyLarge)
                .foregroundStyle(DraftrColor.snow)
            Text(hint(for: kind))
                .font(DraftrFont.bodySmall)
                .foregroundStyle(DraftrColor.snow3)
                .lineLimit(2)
        }
        .padding(DraftrSpace.m)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(DraftrColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
    }

    private func icon(for kind: SceneElementKind) -> DraftrIcon {
        switch kind {
        case .heading:       return .scenes
        case .action:        return .action
        case .character:     return .characters
        case .dialogue:      return .dialogue
        case .parenthetical: return .parens
        case .transition:    return .transition
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
        }
    }
}
