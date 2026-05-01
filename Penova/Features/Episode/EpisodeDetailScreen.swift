//
//  EpisodeDetailScreen.swift
//  Penova
//
//  S08 — Scene list for one episode. Ordered list of SceneItems, FAB
//  opens New Scene sheet (S09), row-tap pushes SceneDetailScreen (S10).
//

import SwiftUI
import SwiftData
import PenovaKit

struct EpisodeDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var episode: Episode

    @State private var showNewScene = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var pendingSceneEdit: ScriptScene?
    @State private var pendingSceneDelete: ScriptScene?

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
                                .contextMenu {
                                    Button("Edit") { pendingSceneEdit = scene }
                                    Button("Delete", role: .destructive) { pendingSceneDelete = scene }
                                }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEdit = true } label: {
                            Label("Edit episode", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete episode", systemImage: "trash")
                        }
                    } label: {
                        PenovaIconView(.more, size: 18, color: PenovaColor.snow)
                    }
                }
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
        .sheet(isPresented: $showEdit) {
            if let project = episode.project {
                NewEpisodeSheet(project: project, editing: episode)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $pendingSceneEdit) { scene in
            NewSceneSheet(episode: episode, editing: scene)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete \(episode.title)?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteEpisode() }
        } message: {
            Text("This removes the episode and all of its scenes.")
        }
        .alert(
            "Delete scene?",
            isPresented: Binding(
                get: { pendingSceneDelete != nil },
                set: { if !$0 { pendingSceneDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingSceneDelete = nil }
            Button("Delete", role: .destructive) { deletePendingScene() }
        } message: {
            Text("This removes the scene and all of its elements.")
        }
    }

    private func deleteEpisode() {
        context.delete(episode)
        try? context.save()
        dismiss()
    }

    private func deletePendingScene() {
        guard let scene = pendingSceneDelete else { return }
        context.delete(scene)
        episode.updatedAt = .now
        try? context.save()
        pendingSceneDelete = nil
    }
}
