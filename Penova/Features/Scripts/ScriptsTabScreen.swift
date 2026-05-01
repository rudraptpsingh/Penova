//
//  ScriptsTabScreen.swift
//  Penova
//
//  S13 — All-projects browser. Filter by status chip (Active / Archived /
//  Trashed), search by title, tap a card to push ProjectDetailScreen.
//

import SwiftUI
import SwiftData
import PenovaKit

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
                            Label("Import from Fountain…", systemImage: "square.and.arrow.down")
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
            // Scoped access: security-scoped URLs are required for document
            // picker results on iOS.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                importError = "Could not read file as text."
                return
            }
            let doc = FountainParser.parse(text)
            let name = url.deletingPathExtension().lastPathComponent
            let title = name.isEmpty ? "Untitled" : name
            _ = FountainImporter.makeProject(title: title, from: doc, context: context)
            try context.save()
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
}
