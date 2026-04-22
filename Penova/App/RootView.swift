//
//  RootView.swift
//  Penova
//
//  Top-level container. Four-tab bottom nav — each tab owns its own
//  NavigationStack so pushes stay scoped.
//

import SwiftUI
import SwiftData

struct RootView: View {
    enum Tab: Hashable { case home, scripts, characters, scenes }
    @State private var selection: Tab = .home

    // Screenshot-mode deep push state: populated on appear if a launch arg
    // routes to a detail screen.
    @State private var scriptsPath = NavigationPath()
    @State private var scenesPath = NavigationPath()

    @Environment(\.modelContext) private var context

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeScreen() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

            NavigationStack(path: $scriptsPath) { ScriptsTabScreen() }
                .tabItem { Label("Scripts", systemImage: "doc.text") }
                .tag(Tab.scripts)

            NavigationStack { CharactersTabScreen() }
                .tabItem { Label("Characters", systemImage: "person.2") }
                .tag(Tab.characters)

            NavigationStack(path: $scenesPath) { ScenesTabScreen() }
                .tabItem { Label("Scenes", systemImage: "rectangle.stack") }
                .tag(Tab.scenes)
        }
        .tint(PenovaColor.amber)
        .onAppear { applyScreenshotRoute() }
    }

    private func applyScreenshotRoute() {
        guard let route = ScreenshotMode.route else { return }
        switch route {
        case .home:       selection = .home
        case .scripts:    selection = .scripts
        case .characters: selection = .characters
        case .scenes:     selection = .scenes
        case .project:
            selection = .scripts
            if let p = try? context.fetch(FetchDescriptor<Project>()).first {
                scriptsPath.append(p)
            }
        case .scene:
            selection = .scenes
            if let s = try? context.fetch(FetchDescriptor<ScriptScene>()).first {
                scenesPath.append(s)
            }
        }
    }
}

#Preview {
    RootView().preferredColorScheme(.dark)
}
