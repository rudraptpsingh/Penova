//
//  ProjectDetailScreen.swift
//  Draftr
//
//  S05 — Project detail. Shows genre/title/logline, a stats row
//  (episodes · scenes · characters), and an ordered list of episodes
//  that push into EpisodeDetailScreen. FAB opens New Episode sheet.
//

import SwiftUI
import SwiftData

struct ProjectDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Bindable var project: Project

    @State private var showNewEpisode = false
    @State private var exportFile: ExportFile?
    @State private var exportError: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: DraftrSpace.l) {
                    header
                    stats
                    DraftrSectionHeader(title: "Episodes")
                    if project.activeEpisodesOrdered.isEmpty {
                        EmptyState(
                            icon: .scripts,
                            title: "No episodes yet.",
                            message: "Add your pilot to start outlining scenes.",
                            ctaTitle: "New episode",
                            ctaAction: { showNewEpisode = true }
                        )
                    } else {
                        VStack(spacing: DraftrSpace.s) {
                            ForEach(project.activeEpisodesOrdered) { ep in
                                NavigationLink(value: ep) {
                                    EpisodeRow(episode: ep)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(DraftrSpace.l)
                .padding(.bottom, DraftrSpace.xxl)
            }
            .background(DraftrColor.ink0)
            .navigationTitle(project.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Episode.self) { ep in
                EpisodeDetailScreen(episode: ep)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            exportPDF()
                        } label: {
                            Label("Export as PDF", systemImage: "doc.richtext")
                        }
                        Button {
                            exportFDX()
                        } label: {
                            Label("Export as FDX", systemImage: "doc.text")
                        }
                    } label: {
                        DraftrIconView(.export, size: 18, color: DraftrColor.snow)
                    }
                }
            }

            if !project.activeEpisodesOrdered.isEmpty {
                DraftrFAB(icon: .plus) { showNewEpisode = true }
                    .padding(DraftrSpace.l)
            }
        }
        .sheet(isPresented: $showNewEpisode) {
            NewEpisodeSheet(project: project)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $exportFile) { file in
            ExportShareSheet(file: file)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Export failed",
               isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
               )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func exportPDF() {
        do {
            let url = try ScriptPDFRenderer.render(project: project)
            exportFile = ExportFile(url: url, format: .pdf)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportFDX() {
        // STUB: FDX writer — real Final Draft XML serializer lands in a later release. See STUBS.md.
        exportError = "FDX export is coming in the next release."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DraftrSpace.s) {
            if !project.genre.isEmpty {
                HStack(spacing: DraftrSpace.s) {
                    ForEach(project.genre, id: \.rawValue) { g in
                        DraftrTag(text: g.display)
                    }
                }
            }
            Text(project.title)
                .font(DraftrFont.hero)
                .foregroundStyle(DraftrColor.snow)
            if !project.logline.isEmpty {
                Text(project.logline)
                    .font(DraftrFont.body)
                    .foregroundStyle(DraftrColor.snow3)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: DraftrSpace.s) {
            StatTile(value: project.episodes.count, label: "Episodes")
            StatTile(value: project.totalSceneCount, label: "Scenes")
            StatTile(value: project.characters.count, label: "Characters")
        }
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: DraftrSpace.xs) {
            Text("\(value)")
                .font(DraftrFont.hero)
                .foregroundStyle(DraftrColor.snow)
            Text(label.uppercased())
                .font(DraftrFont.labelCaps)
                .tracking(DraftrTracking.labelCaps)
                .foregroundStyle(DraftrColor.snow3)
        }
        .padding(DraftrSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DraftrColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    var body: some View {
        HStack(spacing: DraftrSpace.m) {
            VStack(alignment: .leading, spacing: DraftrSpace.xs) {
                Text(episode.title)
                    .font(DraftrFont.bodyLarge)
                    .foregroundStyle(DraftrColor.snow)
                Text("\(episode.scenes.count) scenes · \(episode.status.rawValue)")
                    .font(DraftrFont.bodySmall)
                    .foregroundStyle(DraftrColor.snow3)
            }
            Spacer()
            DraftrIconView(.back, size: 14, color: DraftrColor.snow4)
                .rotationEffect(.degrees(180))
        }
        .padding(DraftrSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DraftrColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
    }
}
