//
//  LibraryWindowView.swift
//  Penova for Mac
//
//  Top of the Mac window. Hosts the three-pane shell: sidebar (library
//  tree) / center (editor or alternate views) / inspector. For now this
//  is a thin stub that proves the target builds and shows the design
//  tokens; subsequent commits flesh out each pane.
//

import SwiftUI
import SwiftData
import PenovaKit

struct LibraryWindowView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    @State private var selectedScene: ScriptScene?
    @State private var sidebarVisible: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisible) {
            LibrarySidebarPlaceholder(
                projects: projects,
                selectedScene: $selectedScene
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            EditorPanePlaceholder(scene: selectedScene)
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        } detail: {
            InspectorPanePlaceholder(scene: selectedScene)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 360)
        }
        .navigationTitle(selectedScene?.heading ?? "Penova")
        .background(PenovaColor.ink0)
        .onAppear {
            if selectedScene == nil {
                selectedScene = projects
                    .flatMap(\.activeEpisodesOrdered)
                    .flatMap(\.scenesOrdered)
                    .first
            }
        }
    }
}

// MARK: - Placeholders (to be replaced)

private struct LibrarySidebarPlaceholder: View {
    let projects: [Project]
    @Binding var selectedScene: ScriptScene?

    var body: some View {
        List(selection: Binding(
            get: { selectedScene?.id },
            set: { id in
                guard let id else { return }
                for p in projects {
                    for ep in p.activeEpisodesOrdered {
                        for s in ep.scenesOrdered where s.id == id {
                            selectedScene = s
                            return
                        }
                    }
                }
            }
        )) {
            Section("Smart") {
                Label("All Scenes", systemImage: "rectangle.stack")
                    .foregroundStyle(PenovaColor.snow2)
                Label("Bookmarked", systemImage: "bookmark")
                    .foregroundStyle(PenovaColor.snow2)
            }
            ForEach(projects) { project in
                Section(project.title) {
                    ForEach(project.activeEpisodesOrdered) { episode in
                        DisclosureGroup {
                            ForEach(episode.scenesOrdered) { scene in
                                Label(scene.heading, systemImage: "doc.text")
                                    .lineLimit(1)
                                    .tag(scene.id)
                            }
                        } label: {
                            Label(episode.title, systemImage: "folder")
                                .foregroundStyle(PenovaColor.snow)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .background(PenovaColor.ink2)
        .scrollContentBackground(.hidden)
    }
}

private struct EditorPanePlaceholder: View {
    let scene: ScriptScene?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let scene {
                    ScriptPagePlaceholder(scene: scene)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Select a scene")
                        .font(PenovaFont.title)
                        .foregroundStyle(PenovaColor.snow3)
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
        }
        .background(PenovaColor.ink0)
    }
}

/// Renders the script paper in the same Roboto-Mono / cream-on-black look
/// as the mockups. Read-only for v1 scaffold; real editor lands in a later
/// commit.
private struct ScriptPagePlaceholder: View {
    let scene: ScriptScene

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(scene.heading)
                .font(.custom("RobotoMono-Medium", size: 14))
                .fontWeight(.semibold)
                .padding(.bottom, 12)
                .textCase(.uppercase)
            ForEach(scene.elementsOrdered) { el in
                ElementRow(element: el)
            }
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 64)
        .frame(width: 640)
        .background(PenovaColor.paper)
        .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 20)
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 4)
    }
}

private struct ElementRow: View {
    let element: SceneElement

    var body: some View {
        let mono = Font.custom("RobotoMono-Medium", size: 14)
        let leading: CGFloat = {
            switch element.kind {
            case .heading, .action, .actBreak: return 0
            case .character:                   return 480 * 0.36
            case .parenthetical:               return 480 * 0.28
            case .dialogue:                    return 480 * 0.18
            case .transition:                  return 0
            }
        }()
        let trailing: CGFloat = element.kind == .dialogue ? 480 * 0.16 : 0
        let isUpper = [SceneElementKind.heading, .character, .transition].contains(element.kind)
        let italic = element.kind == .parenthetical

        HStack {
            if element.kind == .transition { Spacer() }
            Text(element.text)
                .font(mono)
                .italic(italic)
                .textCase(isUpper ? .uppercase : nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 480 - leading - trailing, alignment: .leading)
                .padding(.leading, leading)
                .padding(.trailing, trailing)
        }
        .padding(.vertical, 4)
    }
}

private struct InspectorPanePlaceholder: View {
    let scene: ScriptScene?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let scene {
                    Group {
                        sectionLabel("Heading")
                        Text(scene.heading)
                            .font(.custom("RobotoMono-Medium", size: 13))
                            .foregroundStyle(PenovaColor.snow)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(PenovaColor.ink3)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        sectionLabel("Beat")
                        Text(scene.beatType?.display ?? "—")
                            .font(PenovaFont.bodyMedium)
                            .foregroundStyle(PenovaColor.snow2)

                        sectionLabel("Bookmarked")
                        Text(scene.bookmarked ? "Yes" : "No")
                            .font(PenovaFont.bodyMedium)
                            .foregroundStyle(PenovaColor.snow2)

                        sectionLabel("Elements")
                        Text("\(scene.elements.count)")
                            .font(PenovaFont.title)
                            .foregroundStyle(PenovaColor.snow)
                    }
                } else {
                    Text("No scene selected")
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PenovaColor.ink2)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(PenovaFont.labelCaps)
            .tracking(PenovaTracking.labelCaps)
            .foregroundStyle(PenovaColor.snow4)
            .padding(.bottom, 4)
    }
}
