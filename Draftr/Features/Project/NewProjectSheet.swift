//
//  NewProjectSheet.swift
//  Draftr
//
//  S06 — Create a new project. Minimal fields: title (required), logline,
//  genre chips. On Create, inserts a Project + a default "Pilot" Episode
//  so scenes have somewhere to live, then dismisses.
//

import SwiftUI
import SwiftData

struct NewProjectSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var logline: String = ""
    @State private var selectedGenres: Set<Genre> = [.drama]

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DraftrSpace.l) {
                    DraftrTextField(
                        label: "Title",
                        text: $title,
                        placeholder: "The Last Train"
                    )
                    DraftrTextField(
                        label: "Logline",
                        text: $logline,
                        placeholder: "One sentence that sells it."
                    )
                    VStack(alignment: .leading, spacing: DraftrSpace.s) {
                        Text("Genre")
                            .font(DraftrFont.labelCaps)
                            .tracking(DraftrTracking.labelCaps)
                            .foregroundStyle(DraftrColor.snow3)
                        FlowLayout(spacing: DraftrSpace.s) {
                            ForEach(Genre.allCases) { genre in
                                DraftrChip(
                                    text: genre.display,
                                    isSelected: selectedGenres.contains(genre)
                                ) {
                                    toggle(genre)
                                }
                            }
                        }
                    }
                    DraftrButton(title: "Create project", variant: .primary) {
                        save()
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                }
                .padding(DraftrSpace.l)
            }
            .background(DraftrColor.ink0)
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DraftrColor.snow3)
                }
            }
        }
    }

    private func toggle(_ genre: Genre) {
        if selectedGenres.contains(genre) {
            if selectedGenres.count > 1 { selectedGenres.remove(genre) }
        } else {
            selectedGenres.insert(genre)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let project = Project(
            title: trimmed,
            logline: logline.trimmingCharacters(in: .whitespaces),
            genre: Array(selectedGenres)
        )
        context.insert(project)

        let pilot = Episode(title: "Pilot", order: 0)
        pilot.project = project
        context.insert(pilot)

        try? context.save()
        dismiss()
    }
}

/// Simple wrap layout for chip rows — SwiftUI's default HStack won't wrap.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > maxWidth {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
