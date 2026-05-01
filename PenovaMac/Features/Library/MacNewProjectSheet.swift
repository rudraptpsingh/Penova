//
//  MacNewProjectSheet.swift
//  Penova for Mac
//
//  Modal sheet that creates a new Project + a default first Episode +
//  a placeholder first Scene so the writer can start typing
//  immediately. Triggered from:
//    · Sidebar "New Project" button
//    · ⌘N keyboard shortcut
//    · File → New Project menu
//

import SwiftUI
import SwiftData
import PenovaKit

struct MacNewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Called with the newly-created project so the parent can
    /// auto-select its starting scene.
    let onCreated: (Project) -> Void

    @State private var title: String = ""
    @State private var logline: String = ""
    @State private var selectedGenres: Set<Genre> = [.drama]
    @State private var firstEpisodeTitle: String = "Pilot"
    @FocusState private var titleFocused: Bool

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(PenovaColor.ink4)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fieldBlock(label: "Title", placeholder: "Untitled") {
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .font(PenovaFont.bodyLarge.weight(.semibold))
                            .focused($titleFocused)
                    }
                    fieldBlock(label: "Logline (optional)", placeholder: "One sentence that sells it.") {
                        TextField("", text: $logline, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(PenovaFont.body)
                            .lineLimit(2...5)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GENRE")
                            .font(PenovaFont.labelTiny)
                            .tracking(PenovaTracking.labelTiny)
                            .foregroundStyle(PenovaColor.snow4)
                        FlowChips(
                            items: Genre.allCases.map(\.display),
                            selectedIndex: -1,
                            multiSelectIndices: Set(Genre.allCases.enumerated().compactMap { i, g in
                                selectedGenres.contains(g) ? i : nil
                            })
                        ) { idx in
                            let genre = Genre.allCases[idx]
                            if selectedGenres.contains(genre) {
                                if selectedGenres.count > 1 { selectedGenres.remove(genre) }
                            } else {
                                selectedGenres.insert(genre)
                            }
                        }
                    }
                    fieldBlock(label: "Starting episode", placeholder: "Pilot / Act 1 / Chapter 1") {
                        TextField("", text: $firstEpisodeTitle)
                            .textFieldStyle(.plain)
                            .font(PenovaFont.body)
                    }
                    Text("We'll create one episode and one empty scene so you can start writing immediately.")
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow4)
                }
                .padding(20)
            }
            Divider().background(PenovaColor.ink4)
            footer
        }
        .frame(width: 480, height: 540)
        .background(PenovaColor.ink2)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("sheet.new-project")
        .onAppear { titleFocused = true }
    }

    // MARK: - Components

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Project")
                    .font(PenovaFont.title)
                    .foregroundStyle(PenovaColor.snow)
                Text("Set up a screenplay. You can change everything later.")
                    .font(.system(size: 13))
                    .foregroundStyle(PenovaColor.snow3)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PenovaColor.snow3)
                    .padding(8)
                    .background(PenovaColor.ink3)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(PenovaColor.snow3)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .keyboardShortcut(.cancelAction)
            Button(action: save) {
                Text("Create Project")
                    .font(PenovaFont.bodyMedium)
                    .foregroundStyle(canSave ? PenovaColor.ink0 : PenovaColor.snow4)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(canSave ? PenovaColor.amber : PenovaColor.ink3)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func fieldBlock<Content: View>(
        label: String,
        placeholder: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
            content()
                .foregroundStyle(PenovaColor.snow)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(PenovaColor.ink1)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let project = Project(
            title: trimmed,
            logline: logline.trimmingCharacters(in: .whitespacesAndNewlines),
            genre: Array(selectedGenres),
            status: .active
        )
        context.insert(project)

        let episode = Episode(
            title: firstEpisodeTitle.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Pilot"
                : firstEpisodeTitle.trimmingCharacters(in: .whitespaces),
            order: 0
        )
        episode.project = project
        context.insert(episode)

        let scene = ScriptScene(
            locationName: "NEW LOCATION",
            location: .interior,
            time: .day,
            order: 0
        )
        scene.episode = episode
        context.insert(scene)

        // Seed an empty action element so the editor has a row to focus
        // on the moment the writer lands in it.
        let starter = SceneElement(kind: .action, text: "", order: 0)
        starter.scene = scene
        context.insert(starter)

        try? context.save()
        PenovaLog.library.info("Created new project '\(trimmed, privacy: .public)' with starter episode + scene")
        // F5 — opt-in usage stats. record() is a no-op when the toggle
        // is off; even when on, only an aggregate counter is captured.
        AnalyticsService.shared.record(.scriptCreated)
        onCreated(project)
        dismiss()
    }
}
