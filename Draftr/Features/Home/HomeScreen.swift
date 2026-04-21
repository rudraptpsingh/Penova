//
//  HomeScreen.swift
//  Draftr
//
//  Home tab — greeting + hero line above the fold, active projects below.
//  Zero-state uses EmptyState with a CTA that opens the New Project sheet;
//  any projects present render as ProjectCards stacked in a single column.
//

import SwiftUI
import SwiftData

struct HomeScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.updatedAt, order: .reverse)
    private var allProjects: [Project]

    private var projects: [Project] {
        allProjects.filter { $0.status == .active }
    }

    @State private var showNewProject = false
    @State private var showQuickCapture = false

    private var greeting: String {
        Copy.home.greeting(forHour: Calendar.current.component(.hour, from: Date()))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: DraftrSpace.l) {
                    header
                    DraftrSectionHeader(title: Copy.home.activeProjectsLabel)
                    if projects.isEmpty {
                        EmptyState(
                            icon: .scripts,
                            title: Copy.emptyStates.homeTitle,
                            message: Copy.emptyStates.homeBody,
                            ctaTitle: Copy.emptyStates.homeCta,
                            ctaAction: { showNewProject = true }
                        )
                    } else {
                        VStack(spacing: DraftrSpace.m) {
                            ForEach(projects) { project in
                                NavigationLink(value: project) {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, DraftrSpace.l)
                .padding(.vertical, DraftrSpace.m)
                .padding(.bottom, DraftrSpace.xxl)
            }
            .background(DraftrColor.ink0)
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
                        DraftrIconView(.settings, size: 18, color: DraftrColor.snow)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showQuickCapture = true } label: {
                        DraftrIconView(.voice, size: 18, color: DraftrColor.amber)
                    }
                    .accessibilityLabel("Quick capture")
                }
            }

            if !projects.isEmpty {
                DraftrFAB(icon: .plus) { showNewProject = true }
                    .padding(DraftrSpace.l)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DraftrSpace.s) {
            Text(greeting)
                .font(DraftrFont.bodyMedium)
                .foregroundStyle(DraftrColor.snow3)
            Text(Copy.home.heroLine)
                .font(DraftrFont.hero)
                .foregroundStyle(DraftrColor.snow)
        }
    }
}

