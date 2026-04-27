//
//  ScriptsTabScreen.swift
//  Penova
//
//  S13 — All-projects browser. Filter by status chip (Active / Archived /
//  Trashed), search by title, tap a card to push ProjectDetailScreen.
//

import SwiftUI
import SwiftData

struct ScriptsTabScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    @State private var filter: ProjectStatus = .active
    @State private var search: String = ""
    @State private var showNewProject = false
    @State private var showImportPicker = false
    @State private var importError: String?
    @State private var showGlobalSearch = false
    @State private var editing: Project?
    @State private var pendingDelete: Project?

    private var filtered: [Project] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return projects.filter { p in
            guard p.status == filter else { return false }
            return q.isEmpty || p.title.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    HStack(spacing: PenovaSpace.s) {
                        ForEach(ProjectStatus.allCases, id: \.rawValue) { status in
                            PenovaChip(
                                text: status.rawValue.capitalized,
                                isSelected: status == filter
                            ) { filter = status }
                        }
                    }

                    if filtered.isEmpty {
                        VStack(spacing: PenovaSpace.m) {
                            EmptyState(
                                icon: .scripts,
                                title: filter == .active ? Copy.emptyStates.scriptsTitle : "Nothing here.",
                                message: filter == .active
                                    ? Copy.emptyStates.scriptsBody
                                    : "Projects with this status will show up here.",
                                ctaTitle: filter == .active ? Copy.emptyStates.scriptsCta : nil,
                                ctaAction: filter == .active ? { showNewProject = true } : nil
                            )
                            // Secondary path: writers arriving with an
                            // existing PDF / FDX / Fountain shouldn't have
                            // to discover the toolbar menu to onboard.
                            if filter == .active {
                                importPromptCard
                                    .padding(.horizontal, PenovaSpace.l)
                            }
                        }
                    } else {
                        VStack(spacing: PenovaSpace.m) {
                            ForEach(filtered) { project in
                                NavigationLink(value: project) {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Edit") { editing = project }
                                    statusActions(for: project)
                                    Button("Delete", role: .destructive) { pendingDelete = project }
                                }
                            }
                        }
                    }
                }
                .padding(PenovaSpace.l)
                .padding(.bottom, PenovaSpace.xxl)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("Scripts")
            .searchable(text: $search, prompt: "Search scripts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showGlobalSearch = true } label: {
                        PenovaIconView(.search, size: 18, color: PenovaColor.snow)
                    }
                    .accessibilityLabel("Search all scripts")
                }
            }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailScreen(project: project)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showNewProject = true
                        } label: {
                            Label("New project", systemImage: "plus")
                        }
                        Button {
                            showImportPicker = true
                        } label: {
                            Label(Copy.scripts.importMenuLabel, systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        PenovaIconView(.plus, size: 18, color: PenovaColor.snow)
                    }
                    .accessibilityLabel("Add")
                }
            }

            PenovaFAB(icon: .plus) { showNewProject = true }
                .padding(PenovaSpace.l)
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editing) { project in
            NewProjectSheet(editing: project)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImportPicker) {
            FountainImportPicker { url in
                handleFountainImport(url: url)
            }
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert(
            "Delete project?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { confirmDelete() }
        } message: {
            Text("Removes “\(pendingDelete?.title ?? "")” and all of its episodes, scenes, and characters.")
        }
    }

    @ViewBuilder
    private func statusActions(for project: Project) -> some View {
        switch project.status {
        case .active:
            Button("Archive") { setStatus(project, .archived) }
        case .archived:
            Button("Restore") { setStatus(project, .active) }
        case .trashed:
            Button("Restore") { setStatus(project, .active) }
        }
    }

    private func setStatus(_ project: Project, _ status: ProjectStatus) {
        project.status = status
        project.updatedAt = .now
        try? context.save()
    }

    private func handleFountainImport(url: URL) {
        do {
            _ = try ScreenplayImporter.importFile(at: url, into: context)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func confirmDelete() {
        guard let project = pendingDelete else { return }
        context.delete(project)
        try? context.save()
        pendingDelete = nil
    }

    /// Secondary onboarding path: a writer arriving with an existing
    /// script shouldn't need to find the toolbar `+` menu. Compact card
    /// rendered under the empty state when there are no active projects.
    private var importPromptCard: some View {
        Button {
            showImportPicker = true
        } label: {
            HStack(spacing: PenovaSpace.m) {
                PenovaIconView(.export, size: 18, color: PenovaColor.amber)
                    .rotationEffect(.degrees(180))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.scripts.importEmptyState)
                        .font(PenovaFont.bodyMedium)
                        .foregroundStyle(PenovaColor.snow)
                    Text(Copy.scripts.importMenuSubtitle)
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
            .overlay(
                RoundedRectangle(cornerRadius: PenovaRadius.md)
                    .stroke(PenovaColor.amber.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.scripts.importEmptyCta)
    }
}
