//
//  EpisodeDetailScreen.swift
//  Penova
//
//  S08 — Scene list for one episode. Ordered list of SceneItems, FAB
//  opens New Scene sheet (S09), row-tap pushes SceneDetailScreen (S10).
//

import SwiftUI
import SwiftData

struct EpisodeDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Bindable var episode: Episode

    @State private var showNewScene = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    PenovaSectionHeader(title: "Scenes")
                    if episode.scenes.isEmpty {
                        EmptyState(
                            icon: .scenes,
                            title: "No scenes yet.",
                            message: "Start with a beat or a location — you can always restructure later.",
                            ctaTitle: "New scene",
                            ctaAction: { showNewScene = true }
                        )
                    } else {
                        VStack(spacing: PenovaSpace.s) {
                            ForEach(episode.scenesOrdered) { scene in
                                NavigationLink(value: scene) {
                                    SceneItem(scene: scene)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(PenovaSpace.l)
                .padding(.bottom, PenovaSpace.xxl)
            }
            .background(PenovaColor.ink0)
            .navigationTitle(episode.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ScriptScene.self) { scene in
                SceneDetailScreen(scene: scene)
            }

            if !episode.scenes.isEmpty {
                PenovaFAB(icon: .plus) { showNewScene = true }
                    .padding(PenovaSpace.l)
            }
        }
        .sheet(isPresented: $showNewScene) {
            NewSceneSheet(episode: episode)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
