//
//  ProjectDetailScreen.swift
//  Penova
//
//  S05 — Project detail. Shows genre/title/logline, a stats row
//  (episodes · scenes · characters), and an ordered list of episodes
//  that push into EpisodeDetailScreen. FAB opens New Episode sheet.
//

import SwiftUI
import SwiftData

struct ProjectDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project

    @State private var showNewEpisode = false
    @State private var exportFile: ExportFile?
    @State private var exportError: String?
    @State private var pageCount: Int = 0
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var pendingEpisodeEdit: Episode?
    @State private var pendingEpisodeDelete: Episode?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    header
                    stats
                    revisionsCard
                    PenovaSectionHeader(title: "Episodes")
                    if project.activeEpisodesOrdered.isEmpty {
                        EmptyState(
                            icon: .scripts,
                            title: "No episodes yet.",
                            message: "Add your pilot to start outlining scenes.",
                            ctaTitle: "New episode",
                            ctaAction: { showNewEpisode = true }
                        )
                    } else {
                        VStack(spacing: PenovaSpace.s) {
                            ForEach(project.activeEpisodesOrdered) { ep in
                                NavigationLink(value: ep) {
                                    EpisodeRow(episode: ep)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Edit") { pendingEpisodeEdit = ep }
                                    Button("Delete", role: .destructive) { pendingEpisodeDelete = ep }
                                }
                            }
                        }
                    }
                }
                .padding(PenovaSpace.l)
                .padding(.bottom, PenovaSpace.xxl)
            }
            .background(PenovaColor.ink0)
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
                        Button {
                            exportFountain()
                        } label: {
                            Label("Export as Fountain (.fountain)", systemImage: "doc.plaintext")
                        }
                    } label: {
                        PenovaIconView(.export, size: 18, color: PenovaColor.snow)
                    }
                    .accessibilityLabel("Export project")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEdit = true } label: {
                            Label("Edit project", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete project", systemImage: "trash")
                        }
                    } label: {
                        PenovaIconView(.more, size: 18, color: PenovaColor.snow)
                    }
                    .accessibilityLabel("Project actions")
                }
            }

            if !project.activeEpisodesOrdered.isEmpty {
                PenovaFAB(icon: .plus) { showNewEpisode = true }
                    .padding(PenovaSpace.l)
            }
        }
        .sheet(isPresented: $showNewEpisode) {
            NewEpisodeSheet(project: project)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEdit) {
            NewProjectSheet(editing: project)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingEpisodeEdit) { ep in
            NewEpisodeSheet(project: project, editing: ep)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $exportFile) { file in
            ExportShareSheet(file: file)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete \(project.title)?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteProject() }
        } message: {
            Text("This removes the project and all its episodes, scenes, and characters. This can't be undone.")
        }
        .alert(
            "Delete episode?",
            isPresented: Binding(
                get: { pendingEpisodeDelete != nil },
                set: { if !$0 { pendingEpisodeDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingEpisodeDelete = nil }
            Button("Delete", role: .destructive) { deletePendingEpisode() }
        } message: {
            Text("This removes “\(pendingEpisodeDelete?.title ?? "")” and all its scenes.")
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

    private func deleteProject() {
        context.delete(project)
        try? context.save()
        dismiss()
    }

    private func deletePendingEpisode() {
        guard let ep = pendingEpisodeDelete else { return }
        context.delete(ep)
        project.updatedAt = .now
        try? context.save()
        pendingEpisodeDelete = nil
    }

    private var revisionsCard: some View {
        NavigationLink {
            RevisionsListScreen(project: project)
        } label: {
            HStack(spacing: PenovaSpace.m) {
                PenovaIconView(.bookmark, size: 18, color: PenovaColor.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revisions")
                        .font(PenovaFont.bodyMedium)
                        .foregroundStyle(PenovaColor.snow)
                    Text(revisionsSubtitle)
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)
                }
                Spacer()
                PenovaIconView(.back, size: 14, color: PenovaColor.snow4)
                    .rotationEffect(.degrees(180))
            }
            .padding(PenovaSpace.m)
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Revisions, \(revisionsSubtitle)")
    }

    private var revisionsSubtitle: String {
        let count = project.revisions.count
        if count == 0 { return "Save a snapshot of this draft" }
        if count == 1 { return "1 revision" }
        return "\(count) revisions"
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
        do {
            let url = try FinalDraftXMLWriter.write(project: project)
            exportFile = ExportFile(url: url, format: .fdx)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportFountain() {
        do {
            let url = try FountainExporter.write(project: project)
            exportFile = ExportFile(url: url, format: .fountain)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            if !project.genre.isEmpty {
                HStack(spacing: PenovaSpace.s) {
                    ForEach(project.genre, id: \.rawValue) { g in
                        PenovaTag(text: g.display)
                    }
                }
            }
            Text(project.title)
                .font(PenovaFont.hero)
                .foregroundStyle(PenovaColor.snow)
            if !project.logline.isEmpty {
                Text(project.logline)
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow3)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: PenovaSpace.s) {
            StatTile(value: project.episodes.count, label: "Episodes")
            StatTile(value: project.totalSceneCount, label: "Scenes")
            StatTile(value: project.characters.count, label: "Characters")
            StatTile(value: pageCount, label: "Pages")
        }
        .onAppear(perform: refreshPageCount)
        .onChange(of: project.updatedAt) { _, _ in refreshPageCount() }
    }

    private func refreshPageCount() {
        pageCount = ScriptPDFRenderer.measurePageCount(project: project)
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text("\(value)")
                .font(PenovaFont.hero)
                .foregroundStyle(PenovaColor.snow)
            Text(label.uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    var body: some View {
        HStack(spacing: PenovaSpace.m) {
            VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                Text(episode.title)
                    .font(PenovaFont.bodyLarge)
                    .foregroundStyle(PenovaColor.snow)
                Text("\(episode.scenes.count) scenes · \(episode.status.rawValue)")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
            }
            Spacer()
            PenovaIconView(.back, size: 14, color: PenovaColor.snow4)
                .rotationEffect(.degrees(180))
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }
}
