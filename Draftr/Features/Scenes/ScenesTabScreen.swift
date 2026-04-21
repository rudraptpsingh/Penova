//
//  ScenesTabScreen.swift
//  Draftr
//
//  S16/S17 — Global scene search. Pulls every scene across projects,
//  filterable by project, location, and time-of-day, with a free-text
//  search over heading + description. Tap to jump into SceneDetailScreen.
//

import SwiftUI
import SwiftData

struct ScenesTabScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScriptScene.updatedAt, order: .reverse) private var scenes: [ScriptScene]

    @State private var search: String = ""
    @State private var locationFilter: SceneLocation?
    @State private var timeFilter: SceneTimeOfDay?
    @State private var bookmarkedOnly: Bool = false

    private var filtered: [ScriptScene] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return scenes.filter { scene in
            if bookmarkedOnly && !scene.bookmarked { return false }
            if let locationFilter, scene.location != locationFilter { return false }
            if let timeFilter, scene.time != timeFilter { return false }
            if q.isEmpty { return true }
            if scene.heading.lowercased().contains(q) { return true }
            if let desc = scene.sceneDescription, desc.lowercased().contains(q) { return true }
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DraftrSpace.l) {
                filterBar

                if filtered.isEmpty {
                    EmptyState(
                        icon: .scenes,
                        title: scenes.isEmpty ? "Your scenes will live here." : "No matches.",
                        message: scenes.isEmpty
                            ? "Once you add scenes to a script, they'll appear here across all projects."
                            : "Try a different search or clear your filters."
                    )
                } else {
                    VStack(spacing: DraftrSpace.s) {
                        ForEach(filtered) { scene in
                            NavigationLink(value: scene) {
                                SceneItem(scene: scene)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(DraftrSpace.l)
        }
        .background(DraftrColor.ink0)
        .navigationTitle("Scenes")
        .searchable(text: $search, prompt: "Search headings and descriptions")
        .navigationDestination(for: ScriptScene.self) { scene in
            SceneDetailScreen(scene: scene)
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: DraftrSpace.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DraftrSpace.s) {
                    DraftrChip(text: "Bookmarked", isSelected: bookmarkedOnly) {
                        bookmarkedOnly.toggle()
                    }
                    ForEach(SceneLocation.allCases, id: \.rawValue) { loc in
                        DraftrChip(text: loc.rawValue, isSelected: locationFilter == loc) {
                            locationFilter = locationFilter == loc ? nil : loc
                        }
                    }
                    ForEach(SceneTimeOfDay.allCases, id: \.rawValue) { time in
                        DraftrChip(text: time.rawValue, isSelected: timeFilter == time) {
                            timeFilter = timeFilter == time ? nil : time
                        }
                    }
                }
            }
        }
    }
}
