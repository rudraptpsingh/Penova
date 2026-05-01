//
//  LibrarySidebar.swift
//  Penova for Mac
//
//  Left pane of the three-pane shell. Project → Episode → Scene tree
//  with smart groups at the top (All Scenes, Bookmarked) and a search
//  field. Selection drives `selectedScene` in the parent.
//

import SwiftUI
import SwiftData
import PenovaKit

enum SmartGroup: String, CaseIterable, Identifiable {
    case allScenes, bookmarked, recentlyEdited
    var id: String { rawValue }
    var label: String {
        switch self {
        case .allScenes:      return "All Scenes"
        case .bookmarked:     return "Bookmarked"
        case .recentlyEdited: return "Recently Edited"
        }
    }
    var icon: String {
        switch self {
        case .allScenes:      return "rectangle.stack"
        case .bookmarked:     return "bookmark"
        case .recentlyEdited: return "clock"
        }
    }

    /// Scenes that belong to this smart group, flattened across all
    /// projects, in the order the group's UI should display them.
    static func scenes(for group: SmartGroup, in projects: [Project]) -> [ScriptScene] {
        let all = projects.flatMap(\.activeEpisodesOrdered).flatMap(\.scenesOrdered)
        switch group {
        case .allScenes:
            return all
        case .bookmarked:
            return all.filter(\.bookmarked)
        case .recentlyEdited:
            return all.sorted { $0.updatedAt > $1.updatedAt }.prefix(20).map { $0 }
        }
    }
}

struct LibrarySidebar: View {
    let projects: [Project]
    @Binding var selectedScene: ScriptScene?
    @Binding var activeSmart: SmartGroup?

    @State private var query: String = ""
    @State private var openedEpisodes: Set<String> = []
    @State private var openedProjects: Set<String> = []
    @State private var hoveredSmart: SmartGroup?
    @State private var hoveredSceneID: String?

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .accessibilityIdentifier(A11yID.sidebarSearch)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Smart groups
                    sectionHeader("Smart")
                    ForEach(SmartGroup.allCases) { group in
                        smartRow(group: group, count: count(for: group))
                    }

                    Spacer().frame(height: 12)

                    // Projects
                    sectionHeader("Projects")
                    ForEach(visibleProjects) { project in
                        projectNode(project)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            Divider().background(PenovaColor.ink4)
            newProjectButton
                .padding(12)
        }
        .background(PenovaColor.ink2)
        .accessibilityIdentifier(A11yID.sidebar)
        .onAppear {
            // Auto-open the first project & first episode so users see scenes
            if let p = projects.first { openedProjects.insert(p.id) }
            if let ep = projects.first?.activeEpisodesOrdered.first {
                openedEpisodes.insert(ep.id)
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PenovaColor.snow4)
                .font(.system(size: 11))
            TextField("Search library", text: $query)
                .textFieldStyle(.plain)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow)
            Text("⌘F")
                .font(.custom("RobotoMono-Medium", size: 10))
                .foregroundStyle(PenovaColor.snow4)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(PenovaColor.ink4)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(PenovaColor.ink3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func smartRow(group: SmartGroup, count: Int) -> some View {
        let isActive  = activeSmart == group
        let isHovered = hoveredSmart == group
        return Button(action: { selectSmart(group) }) {
            HStack(spacing: 8) {
                Image(systemName: group.icon)
                    .foregroundStyle(isActive ? PenovaColor.amber : PenovaColor.snow3)
                    .frame(width: 14)
                Text(group.label)
                    .font(PenovaFont.body)
                    .foregroundStyle(isActive ? PenovaColor.snow : PenovaColor.snow2)
                    .fontWeight(isActive ? .medium : .regular)
                Spacer()
                Text("\(count)")
                    .font(.custom("RobotoMono-Medium", size: 11))
                    .foregroundStyle(PenovaColor.snow4)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(
                ZStack(alignment: .leading) {
                    if isActive {
                        RoundedRectangle(cornerRadius: 6).fill(PenovaColor.ink3)
                        Rectangle()
                            .fill(PenovaColor.amber)
                            .frame(width: 3)
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                            .padding(.vertical, 4)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6).fill(PenovaColor.ink3.opacity(0.6))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSmart = hovering ? group : (hoveredSmart == group ? nil : hoveredSmart)
        }
    }

    private func count(for group: SmartGroup) -> Int {
        switch group {
        case .allScenes:      return allScenes.count
        case .bookmarked:     return bookmarkedCount
        case .recentlyEdited: return min(8, allScenes.count)
        }
    }

    private func selectSmart(_ group: SmartGroup) {
        // Toggle off if already active
        if activeSmart == group {
            activeSmart = nil
            return
        }
        activeSmart = group
        let scenes = SmartGroup.scenes(for: group, in: projects)
        PenovaLog.library.info("smart group: \(group.rawValue, privacy: .public), \(scenes.count) scenes")
    }

    // MARK: - Tree

    private func projectNode(_ project: Project) -> some View {
        let isOpen = openedProjects.contains(project.id)
        return VStack(alignment: .leading, spacing: 0) {
            disclosureRow(
                title: project.title,
                systemImage: "folder",
                count: project.totalSceneCount,
                indent: 0,
                isOpen: isOpen,
                onToggle: { toggle(&openedProjects, project.id) }
            )
            if isOpen {
                ForEach(project.activeEpisodesOrdered) { episode in
                    episodeNode(episode)
                }
            }
        }
    }

    private func episodeNode(_ episode: Episode) -> some View {
        let isOpen = openedEpisodes.contains(episode.id)
        return VStack(alignment: .leading, spacing: 0) {
            disclosureRow(
                title: episode.title,
                systemImage: nil,
                count: episode.scenes.count,
                indent: 1,
                isOpen: isOpen,
                onToggle: { toggle(&openedEpisodes, episode.id) }
            )
            if isOpen {
                ForEach(filteredScenes(in: episode)) { scene in
                    sceneRow(scene)
                }
            }
        }
    }

    private func sceneRow(_ scene: ScriptScene) -> some View {
        let isSelected = selectedScene?.id == scene.id
        let isHovered  = hoveredSceneID == scene.id
        return Button(action: {
            selectedScene = scene
            activeSmart = nil
        }) {
            HStack(spacing: 8) {
                Spacer().frame(width: 32)
                Text(scene.heading)
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(isSelected ? PenovaColor.snow : PenovaColor.snow2)
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if scene.bookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(PenovaColor.amber)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .background(
                ZStack(alignment: .leading) {
                    if isSelected {
                        Rectangle()
                            .fill(PenovaColor.ink3)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Rectangle()
                            .fill(PenovaColor.amber)
                            .frame(width: 3)
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                            .padding(.vertical, 4)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6).fill(PenovaColor.ink3.opacity(0.5))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSceneID = hovering ? scene.id : (hoveredSceneID == scene.id ? nil : hoveredSceneID)
        }
    }

    private func disclosureRow(
        title: String,
        systemImage: String?,
        count: Int,
        indent: Int,
        isOpen: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Spacer().frame(width: CGFloat(indent * 16))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(PenovaColor.snow4)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 10)
                    .animation(.easeOut(duration: 0.12), value: isOpen)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11))
                        .foregroundStyle(PenovaColor.snow3)
                        .frame(width: 14)
                }
                Text(title)
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow)
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.custom("RobotoMono-Medium", size: 10))
                    .foregroundStyle(PenovaColor.snow4)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private var newProjectButton: some View {
        Button(action: {
            NotificationCenter.default.post(name: .penovaNewProject, object: nil)
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("New Project")
            }
            .font(PenovaFont.bodyMedium)
            .foregroundStyle(PenovaColor.snow3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(PenovaColor.ink5, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived

    private var allScenes: [ScriptScene] {
        projects.flatMap(\.activeEpisodesOrdered).flatMap(\.scenesOrdered)
    }
    private var bookmarkedCount: Int { allScenes.filter(\.bookmarked).count }

    private var visibleProjects: [Project] {
        guard !query.isEmpty else { return projects }
        let q = query.lowercased()
        return projects.filter { project in
            project.title.lowercased().contains(q)
                || project.activeEpisodesOrdered.contains { ep in
                    ep.scenesOrdered.contains { $0.heading.lowercased().contains(q) }
                }
        }
    }

    private func filteredScenes(in episode: Episode) -> [ScriptScene] {
        guard !query.isEmpty else { return episode.scenesOrdered }
        let q = query.lowercased()
        return episode.scenesOrdered.filter {
            $0.heading.lowercased().contains(q)
                || $0.elements.contains { $0.text.lowercased().contains(q) }
        }
    }
}
