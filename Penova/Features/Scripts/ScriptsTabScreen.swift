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
                        EmptyState(
                            icon: .scripts,
                            title: filter == .active ? Copy.emptyStates.scriptsTitle : "Nothing here.",
                            message: filter == .active
                                ? Copy.emptyStates.scriptsBody
                                : "Projects with this status will show up here.",
                            ctaTitle: filter == .active ? Copy.emptyStates.scriptsCta : nil,
                            ctaAction: filter == .active ? { showNewProject = true } : nil
                        )
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

    private func confirmDelete() {
        guard let project = pendingDelete else { return }
        context.delete(project)
        try? context.save()
        pendingDelete = nil
    }
}
