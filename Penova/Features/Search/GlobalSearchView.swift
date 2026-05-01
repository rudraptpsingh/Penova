//
//  GlobalSearchView.swift
//  Penova
//
//  Script-wide search. Presented as a sheet from ScriptsTabScreen. Matches
//  against SceneElement text and ScriptCharacter names, grouped by
//  Project → Episode → Scene. Tapping a result deep-links via AppRouter.
//
//  Implementation note on SwiftData #Predicate:
//    The compiler couldn't resolve `localizedStandardContains` inside a
//    #Predicate against SceneElement at the time this was written, so we
//    fetch everything and filter in-memory using String.localizedCaseInsensitiveContains.
//    For the current "one active project on free" ceiling (≤500 scenes) the
//    in-memory cost is trivial. Revisit if we ever see projects in the
//    tens of thousands of elements.
//

import SwiftUI
import SwiftData
import Combine
import PenovaKit

struct GlobalSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: AppRouter

    @State private var query: String = ""
    @State private var debounced: String = ""
    @State private var elementHits: [SceneElement] = []
    @State private var characterHits: [ScriptCharacter] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider().background(PenovaColor.ink2)
                if debounced.trimmingCharacters(in: .whitespaces).isEmpty {
                    hint
                } else if elementHits.isEmpty && characterHits.isEmpty {
                    empty
                } else {
                    results
                }
            }
            .background(PenovaColor.ink0)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
        }
            .preferredColorScheme(.dark)
        .onChange(of: query) { _, newValue in
            scheduleDebounce(newValue)
        }
        .onChange(of: debounced) { _, _ in runQuery() }
    }

    private var searchField: some View {
        HStack(spacing: PenovaSpace.s) {
            PenovaIconView(.search, size: 16, color: PenovaColor.snow3)
            TextField("Search every scene, line, and character…", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(PenovaColor.snow)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    PenovaIconView(.close, size: 14, color: PenovaColor.snow4)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(PenovaSpace.m)
    }

    private var hint: some View {
        VStack(spacing: PenovaSpace.s) {
            Spacer()
            Text("Type to search across every project.")
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow3)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var empty: some View {
        VStack(spacing: PenovaSpace.s) {
            Spacer()
            Text("No matches for \u{201C}\(debounced)\u{201D}.")
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow3)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                if !characterHits.isEmpty {
                    VStack(alignment: .leading, spacing: PenovaSpace.s) {
                        Text("Characters")
                            .font(PenovaFont.labelCaps)
                            .tracking(PenovaTracking.labelCaps)
                            .foregroundStyle(PenovaColor.snow3)
                        ForEach(characterHits, id: \.id) { ch in
                            HStack {
                                Text(ch.name)
                                    .font(PenovaFont.body)
                                    .foregroundStyle(PenovaColor.snow)
                                Spacer()
                                Text(ch.role.display)
                                    .font(PenovaFont.bodySmall)
                                    .foregroundStyle(PenovaColor.snow3)
                            }
                            .padding(PenovaSpace.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PenovaColor.ink2)
                            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                        }
                    }
                }

                ForEach(groupedHits, id: \.projectID) { group in
                    VStack(alignment: .leading, spacing: PenovaSpace.s) {
                        Text(group.projectTitle)
                            .font(PenovaFont.labelCaps)
                            .tracking(PenovaTracking.labelCaps)
                            .foregroundStyle(PenovaColor.snow3)
                        ForEach(group.scenes, id: \.sceneID) { row in
                            Button {
                                router.pendingSceneID = row.sceneID
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                                    Text("\(row.episodeTitle) · \(row.sceneHeading)")
                                        .font(PenovaFont.bodySmall)
                                        .foregroundStyle(PenovaColor.snow3)
                                    Text(row.snippet)
                                        .font(PenovaFont.monoScript)
                                        .foregroundStyle(PenovaColor.snow)
                                        .lineLimit(2)
                                }
                                .padding(PenovaSpace.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PenovaColor.ink2)
                                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(PenovaSpace.l)
        }
    }

    // MARK: Debounce

    @State private var debounceTask: Task<Void, Never>?

    private func scheduleDebounce(_ value: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }
            await MainActor.run { debounced = value }
        }
    }

    // MARK: Query

    private func runQuery() {
        let q = debounced.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            elementHits = []
            characterHits = []
            return
        }
        // In-memory filter for elements (see file header for the rationale).
        let allElements = (try? context.fetch(FetchDescriptor<SceneElement>())) ?? []
        elementHits = allElements
            .filter { $0.text.localizedCaseInsensitiveContains(q) }
            .prefix(50)
            .map { $0 }

        let allCharacters = (try? context.fetch(FetchDescriptor<ScriptCharacter>())) ?? []
        characterHits = allCharacters
            .filter { $0.name.localizedCaseInsensitiveContains(q) }
            .prefix(20)
            .map { $0 }
    }

    // MARK: Grouping

    private struct SceneHitRow {
        let sceneID: ID
        let sceneHeading: String
        let episodeTitle: String
        let snippet: String
    }
    private struct ProjectGroup {
        let projectID: ID
        let projectTitle: String
        let scenes: [SceneHitRow]
    }

    private var groupedHits: [ProjectGroup] {
        var byProject: [ID: (title: String, scenes: [ID: SceneHitRow])] = [:]
        for el in elementHits {
            guard let scene = el.scene,
                  let episode = scene.episode,
                  let project = episode.project else { continue }
            let row = SceneHitRow(
                sceneID: scene.id,
                sceneHeading: scene.heading,
                episodeTitle: episode.title,
                snippet: snippet(from: el.text, query: debounced)
            )
            var entry = byProject[project.id] ?? (title: project.title, scenes: [:])
            // Only keep the first hit per scene — the row still links to the
            // whole scene, so showing ten matches for the same scene adds
            // noise without new information.
            if entry.scenes[scene.id] == nil {
                entry.scenes[scene.id] = row
            }
            byProject[project.id] = entry
        }
        return byProject.map { (id, value) in
            ProjectGroup(
                projectID: id,
                projectTitle: value.title,
                scenes: Array(value.scenes.values).sorted { $0.sceneHeading < $1.sceneHeading }
            )
        }
        .sorted { $0.projectTitle < $1.projectTitle }
    }

    /// A one-line snippet centred (loosely) on the matched substring, so the
    /// row shows the context of the match rather than the start of a
    /// paragraph that might not contain the query at all in its first 60 chars.
    private func snippet(from text: String, query: String) -> String {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty,
              let range = text.range(of: q, options: .caseInsensitive)
        else { return String(text.prefix(120)) }
        let before = 32
        let after = 80
        let startDist = text.distance(from: text.startIndex, to: range.lowerBound)
        let lowerOffset = max(0, startDist - before)
        let upperOffset = min(text.count, startDist + after)
        let lower = text.index(text.startIndex, offsetBy: lowerOffset)
        let upper = text.index(text.startIndex, offsetBy: upperOffset)
        var slice = String(text[lower..<upper])
        if lowerOffset > 0 { slice = "…" + slice }
        if upperOffset < text.count { slice += "…" }
        return slice
    }
}
