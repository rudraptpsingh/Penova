//
//  LibraryWindowView.swift
//  Penova for Mac
//
//  Three-pane shell: library sidebar / editor / inspector. Hosts the
//  toolbar (New Scene, Print, Export, view toggle) and the status bar
//  with live page count + sync indicator. The editor pane swaps between
//  Editor / Index Cards / Outline based on `viewMode`.
//

import SwiftUI
import SwiftData
import PenovaKit

enum CenterViewMode: String, CaseIterable, Identifiable {
    case editor, cards, outline
    var id: String { rawValue }
    var label: String {
        switch self {
        case .editor: return "Editor"
        case .cards:  return "Index Cards"
        case .outline: return "Outline"
        }
    }
    var symbol: String {
        switch self {
        case .editor:  return "doc.text"
        case .cards:   return "rectangle.grid.2x2"
        case .outline: return "list.bullet.rectangle"
        }
    }
}

struct LibraryWindowView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    @State private var selectedScene: ScriptScene?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var viewMode: CenterViewMode = .editor
    @State private var inspectorVisible: Bool = true
    @State private var focusMode: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            LibrarySidebar(
                projects: projects,
                selectedScene: $selectedScene
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            HStack(spacing: 0) {
                centerPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if inspectorVisible && !focusMode {
                    Divider().background(PenovaColor.ink4)
                    SceneInspector(scene: selectedScene)
                        .frame(width: 300)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .background(PenovaColor.ink0)
        .toolbar {
            if !focusMode {
                toolbarContent
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !focusMode {
                StatusBar(
                    pages: pageEstimate,
                    isSynced: true,
                    sceneCount: totalSceneCount
                )
            }
        }
        .overlay(alignment: .bottom) {
            if focusMode {
                focusPill
            }
        }
        .onAppear {
            if selectedScene == nil {
                selectedScene = projects
                    .flatMap(\.activeEpisodesOrdered)
                    .flatMap(\.scenesOrdered)
                    .first
            }
        }
    }

    // MARK: - Navigation title

    private var navigationTitle: String {
        guard let scene = selectedScene else { return "Penova" }
        if let ep = scene.episode, let proj = ep.project {
            return "\(proj.title) — \(ep.title) — \(scene.heading)"
        }
        return scene.heading
    }

    private var totalSceneCount: Int {
        projects.reduce(0) { $0 + $1.totalSceneCount }
    }

    private var pageEstimate: String {
        guard let scene = selectedScene else { return "—" }
        // Crude estimate: ~55 lines per page, action ~1 line, dialogue ~1.5
        let lines = scene.elements.reduce(0.0) { acc, el in
            switch el.kind {
            case .heading, .character: return acc + 1
            case .parenthetical: return acc + 0.6
            case .dialogue: return acc + Double(max(1, el.text.count / 35))
            case .action: return acc + Double(max(1, el.text.count / 60))
            case .transition, .actBreak: return acc + 1.5
            }
        }
        let pages = lines / 55.0
        return String(format: "%.1f pp", pages)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: newScene) {
                Label("New Scene", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(PenovaColor.amber)
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Button(action: { /* print */ }) {
                Label("Print", systemImage: "printer")
            }
            .keyboardShortcut("p", modifiers: .command)

            Menu {
                Button("Export PDF…") {}.keyboardShortcut("e", modifiers: .command)
                Button("Export Final Draft (FDX)…") {}
                Button("Export Fountain…") {}
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }

        ToolbarItem(placement: .principal) {
            Picker("", selection: $viewMode) {
                ForEach(CenterViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleOnly)
            .frame(width: 280)
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { focusMode.toggle() }) {
                Label("Focus Mode", systemImage: focusMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { inspectorVisible.toggle() }) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
        }
    }

    // MARK: - Center pane (editor / cards / outline)

    @ViewBuilder
    private var centerPane: some View {
        switch viewMode {
        case .editor:
            ScriptEditorPane(scene: selectedScene)
        case .cards:
            IndexCardsPane(projects: projects, selectedScene: $selectedScene)
        case .outline:
            OutlinePane(projects: projects, selectedScene: $selectedScene)
        }
    }

    // MARK: - Focus mode pill

    private var focusPill: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .foregroundStyle(PenovaColor.amber)
                .font(.system(size: 11))
            Text("Focus")
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow3)
            Text("·").foregroundStyle(PenovaColor.ink5)
            Text(pageEstimate)
                .font(.custom("RobotoMono-Medium", size: 11))
                .foregroundStyle(PenovaColor.snow)
            Text("·").foregroundStyle(PenovaColor.ink5)
            Button(action: { focusMode = false }) {
                HStack(spacing: 6) {
                    Text("Exit").foregroundStyle(PenovaColor.snow4)
                    Text("⎋")
                        .font(.custom("RobotoMono-Medium", size: 10))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(PenovaColor.ink3)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .font(PenovaFont.bodySmall)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(PenovaColor.ink4, lineWidth: 1))
        .padding(.bottom, 24)
        .keyboardShortcut(.escape)
    }

    private func newScene() {
        guard let firstEp = projects.first?.activeEpisodesOrdered.first else { return }
        let nextOrder = (firstEp.scenes.map(\.order).max() ?? -1) + 1
        let scene = ScriptScene(
            locationName: "NEW LOCATION",
            location: .interior,
            time: .day,
            order: nextOrder
        )
        scene.episode = firstEp
        context.insert(scene)
        try? context.save()
        selectedScene = scene
    }
}

// MARK: - Status bar

private struct StatusBar: View {
    let pages: String
    let isSynced: Bool
    let sceneCount: Int

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("Pages")
                    .foregroundStyle(PenovaColor.snow4)
                Text(pages)
                    .foregroundStyle(PenovaColor.snow2)
                    .fontWeight(.medium)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(isSynced ? PenovaColor.jade : PenovaColor.amber)
                    .frame(width: 6, height: 6)
                Text(isSynced ? "Synced" : "Syncing")
                    .foregroundStyle(PenovaColor.snow4)
            }
            Spacer()
            Text("\(sceneCount) scenes")
                .foregroundStyle(PenovaColor.snow4)
            Text("Penova v0.1.0")
                .foregroundStyle(PenovaColor.snow4)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(PenovaColor.ink2)
        .overlay(Rectangle().fill(PenovaColor.ink4).frame(height: 1), alignment: .top)
    }
}
