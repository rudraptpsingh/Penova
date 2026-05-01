//
//  NewEpisodeSheet.swift
//  Penova
//
//  S07 — Create an episode inside a project. Order auto-increments to
//  append at the end; user edits title only.
//

import SwiftUI
import SwiftData
import PenovaKit

struct NewEpisodeSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project
    var editing: Episode? = nil

    @State private var title: String = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var nextOrder: Int {
        (project.episodes.map(\.order).max() ?? -1) + 1
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                PenovaTextField(
                    label: "Title",
                    text: $title,
                    placeholder: nextOrder == 0 ? "Pilot" : "Episode \(nextOrder + 1)"
                )
                PenovaButton(title: editing == nil ? "Create episode" : "Save changes", variant: .primary) { save() }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                Spacer()
            }
            .padding(PenovaSpace.l)
            .background(PenovaColor.ink0)
            .navigationTitle(editing == nil ? "New episode" : "Edit episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
            .onAppear {
                if let ep = editing { title = ep.title }
            }
        }
            .preferredColorScheme(.dark)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if let ep = editing {
            ep.title = trimmed
            ep.updatedAt = .now
        } else {
            let ep = Episode(title: trimmed, order: nextOrder)
            ep.project = project
            context.insert(ep)
        }
        project.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
