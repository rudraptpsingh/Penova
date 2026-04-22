//
//  HomeScreen.swift
//  Penova
//
//  Home tab — greeting + hero line above the fold, active projects below.
//  Zero-state uses EmptyState with a CTA that opens the New Project sheet;
//  any projects present render as ProjectCards stacked in a single column.
//

import SwiftUI
import SwiftData

struct HomeScreen: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \Project.updatedAt, order: .reverse)
    private var allProjects: [Project]
    @Query private var allScenes: [ScriptScene]

    private var projects: [Project] {
        allProjects.filter { $0.status == .active }
    }

    /// Last scene the user opened in this or a previous session. Looked up
    /// against all scenes by id — nil if none recorded or the scene was
    /// deleted since, in which case the resume card is hidden entirely.
    private var resumeScene: ScriptScene? {
        guard let id = UserDefaults.standard.string(forKey: "penova.lastOpenedSceneID"),
              !id.isEmpty else { return nil }
        return allScenes.first(where: { $0.id == id })
    }

    @State private var showNewProject = false
    @State private var showQuickCapture = false
    /// Per-project page-count cache, keyed by project.id + updatedAt signature.
    @State private var pageCountByProject: [String: (stamp: Date, pages: Int)] = [:]

    private var greeting: String {
        Copy.home.greeting(forHour: Calendar.current.component(.hour, from: Date()))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    header
                    if let scene = resumeScene {
                        resumeCard(for: scene)
                    }
                    PenovaSectionHeader(title: Copy.home.activeProjectsLabel)
                    if projects.isEmpty {
                        EmptyState(
                            icon: .scripts,
                            title: Copy.emptyStates.homeTitle,
                            message: Copy.emptyStates.homeBody,
                            ctaTitle: Copy.emptyStates.homeCta,
                            ctaAction: { showNewProject = true }
                        )
                    } else {
                        VStack(spacing: PenovaSpace.m) {
                            ForEach(projects) { project in
                                NavigationLink(value: project) {
                                    ProjectCard(project: project, pageCount: pageCount(for: project))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, PenovaSpace.l)
                .padding(.vertical, PenovaSpace.m)
                .padding(.bottom, PenovaSpace.xxl)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Project.self) { project in
                ProjectDetailScreen(project: project)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsScreen()
                    } label: {
                        PenovaIconView(.settings, size: 18, color: PenovaColor.snow)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showQuickCapture = true } label: {
                        PenovaIconView(.voice, size: 18, color: PenovaColor.amber)
                    }
                    .accessibilityLabel("Quick capture")
                }
            }

            if !projects.isEmpty {
                PenovaFAB(icon: .plus) { showNewProject = true }
                    .padding(PenovaSpace.l)
            }
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showQuickCapture) {
            VoiceCaptureSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: refreshPageCounts)
        .onChange(of: allProjects.count) { _, _ in refreshPageCounts() }
        .onChange(of: allProjects.map(\.updatedAt)) { _, _ in refreshPageCounts() }
    }

    /// Read the cached page count for a project. If not yet measured, returns
    /// nil and the card hides the meta entry until `refreshPageCounts()` runs.
    private func pageCount(for project: Project) -> Int? {
        guard let entry = pageCountByProject[project.id],
              entry.stamp == project.updatedAt else { return nil }
        return entry.pages
    }

    /// Populate / refresh the cache for the currently visible projects.
    /// Cheap: just skips entries whose `updatedAt` hasn't changed.
    private func refreshPageCounts() {
        for project in projects {
            if pageCountByProject[project.id]?.stamp == project.updatedAt { continue }
            let pages = ScriptPDFRenderer.measurePageCount(project: project)
            pageCountByProject[project.id] = (project.updatedAt, pages)
        }
    }

    private func resumeCard(for scene: ScriptScene) -> some View {
        Button {
            router.pendingSceneID = scene.id
        } label: {
            HStack(alignment: .center, spacing: PenovaSpace.m) {
                PenovaIconView(.clock, size: 18, color: PenovaColor.amber)
                VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                    Text("Resume")
                        .font(PenovaFont.labelCaps)
                        .tracking(PenovaTracking.labelCaps)
                        .foregroundStyle(PenovaColor.snow3)
                    Text(scene.heading)
                        .font(PenovaFont.monoScript)
                        .foregroundStyle(PenovaColor.snow)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                PenovaIconView(.back, size: 14, color: PenovaColor.snow4)
                    .rotationEffect(.degrees(180))
            }
            .padding(PenovaSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resume \(scene.heading)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text(greeting)
                .font(PenovaFont.bodyMedium)
                .foregroundStyle(PenovaColor.snow3)
            Text(Copy.home.heroLine)
                .font(PenovaFont.hero)
                .foregroundStyle(PenovaColor.snow)
        }
    }
}

