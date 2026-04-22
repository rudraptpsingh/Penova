//
//  NewProjectSheet.swift
//  Penova
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
    var editing: Project? = nil

    @State private var title: String = ""
    @State private var logline: String = ""
    @State private var selectedGenres: Set<Genre> = [.drama]
    @State private var contactBlock: String = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    PenovaTextField(
                        label: "Title",
                        text: $title,
                        placeholder: "The Last Train"
                    )
                    PenovaTextField(
                        label: "Logline",
                        text: $logline,
                        placeholder: "One sentence that sells it."
                    )
                    VStack(alignment: .leading, spacing: PenovaSpace.s) {
                        Text("Genre")
                            .font(PenovaFont.labelCaps)
                            .tracking(PenovaTracking.labelCaps)
                            .foregroundStyle(PenovaColor.snow3)
                        FlowLayout(spacing: PenovaSpace.s) {
                            ForEach(Genre.allCases) { genre in
                                PenovaChip(
                                    text: genre.display,
                                    isSelected: selectedGenres.contains(genre)
                                ) {
                                    toggle(genre)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: PenovaSpace.s) {
                        Text("Contact (title page)")
                            .font(PenovaFont.labelCaps)
                            .tracking(PenovaTracking.labelCaps)
                            .foregroundStyle(PenovaColor.snow3)
                        ZStack(alignment: .topLeading) {
                            if contactBlock.isEmpty {
                                Text("name@email.com\n+1 555 0100\nAgent: ...")
                                    .font(PenovaFont.body)
                                    .foregroundStyle(PenovaColor.snow4)
                                    .padding(.horizontal, PenovaSpace.m)
                                    .padding(.vertical, PenovaSpace.s + 2)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $contactBlock)
                                .font(PenovaFont.body)
                                .foregroundStyle(PenovaColor.snow)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, PenovaSpace.s)
                                .padding(.vertical, PenovaSpace.xs)
                                .frame(minHeight: 96)
                        }
                        .background(PenovaColor.ink2)
                        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
                    }
                    PenovaButton(title: editing == nil ? "Create project" : "Save changes", variant: .primary) {
                        save()
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle(editing == nil ? "New project" : "Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
            .onAppear(perform: hydrate)
        }
    }

    private func hydrate() {
        guard let p = editing else { return }
        title = p.title
        logline = p.logline
        selectedGenres = Set(p.genre.isEmpty ? [.drama] : p.genre)
        contactBlock = p.contactBlock
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
        if let p = editing {
            p.title = trimmed
            p.logline = logline.trimmingCharacters(in: .whitespaces)
            p.genre = Array(selectedGenres)
            p.contactBlock = contactBlock
            p.updatedAt = .now
        } else {
            let project = Project(
                title: trimmed,
                logline: logline.trimmingCharacters(in: .whitespaces),
                genre: Array(selectedGenres)
            )
            project.contactBlock = contactBlock
            context.insert(project)

            let pilot = Episode(title: "Pilot", order: 0)
            pilot.project = project
            context.insert(pilot)
        }
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
