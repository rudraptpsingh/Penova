//
//  RootView.swift
//  Draftr
//
//  Top-level container. Four-tab bottom nav — each tab owns its own
//  NavigationStack so pushes stay scoped.
//
//  Screens are stubbed with placeholder bodies until their milestones land.
//  The point of this file is to prove the navigation skeleton and the
//  design-system tokens work end to end.
//

import SwiftUI

struct RootView: View {
    enum Tab: Hashable { case home, scripts, characters, scenes }
    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeScreen() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

            NavigationStack { ScriptsTabScreen() }
                .tabItem { Label("Scripts", systemImage: "doc.text") }
                .tag(Tab.scripts)

            NavigationStack { CharactersTabScreen() }
                .tabItem { Label("Characters", systemImage: "person.2") }
                .tag(Tab.characters)

            NavigationStack { ScenesTabScreen() }
                .tabItem { Label("Scenes", systemImage: "rectangle.stack") }
                .tag(Tab.scenes)
        }
        .tint(DraftrColor.amber)
    }
}

#Preview {
    RootView().preferredColorScheme(.dark)
}
