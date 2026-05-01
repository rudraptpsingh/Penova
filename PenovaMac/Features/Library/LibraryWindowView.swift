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
    @State private var activeSmart: SmartGroup?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var viewMode: CenterViewMode = .editor
    @State private var inspectorVisible: Bool = true
    @State private var focusMode: Bool = false
    @State private var searchVisible: Bool = false
    @State private var titlePageEditorVisible: Bool = false
    @State private var exportSheetVisible: Bool = false
    @State private var newProjectVisible: Bool = false
    @State private var pendingExportFormat: MacExportFormat = .pdf

    var body: some View {
        baseShell
            .accessibilityIdentifier(A11yID.libraryWindow)
            .modifier(SheetsAndOverlays(
                searchVisible: $searchVisible,
                titlePageVisible: $titlePageEditorVisible,
                exportVisible: $exportSheetVisible,
                newProjectVisible: $newProjectVisible,
                projects: projects,
                exportTarget: currentExportEpisode,
                titlePageProject: currentProject,
                onSelectScene: { selectedScene = $0 },
                onProjectCreated: { project in
                    if let firstScene = project.activeEpisodesOrdered.first?.scenesOrdered.first {
                        selectedScene = firstScene
                        activeSmart = nil
                    }
                }
            ))
            .background(hiddenShortcuts)
            .onAppear {
                if selectedScene == nil {
                    selectedScene = projects
                        .flatMap(\.activeEpisodesOrdered)
                        .flatMap(\.scenesOrdered)
                        .first
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .penovaNewProject)) { _ in
                newProjectVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .penovaNewScene)) { _ in
                newScene()
            }
    }

    private var baseShell: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                LibrarySidebar(
                    projects: projects,
                    selectedScene: $selectedScene,
                    activeSmart: $activeSmart
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
            .toolbar {
                if !focusMode {
                    toolbarContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Status bar lives BELOW the split view as a peer so it
            // applies to both sidebar and detail simultaneously. Using
            // safeAreaInset on the NavigationSplitView only insets the
            // detail column on macOS.
            if !focusMode {
                StatusBar(
                    pages: pageEstimate,
                    isSynced: true,
                    sceneCount: totalSceneCount
                )
            }
        }
        .background(PenovaColor.ink0)
        .overlay(alignment: .bottom) {
            if focusMode { focusPill }
        }
    }

    @ViewBuilder
    private var hiddenShortcuts: some View {
        Group {
            Button("") { searchVisible = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
            Button("") { titlePageEditorVisible = true }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .opacity(0)
            Button("") { exportSheetVisible = true }
                .keyboardShortcut("e", modifiers: .command)
                .opacity(0)

            // ⌘1–⌘7 set the focused element's kind directly (Final Draft
            // / Highland / Fade In all expose this same chord).
            ForEach(Array(SceneElementKind.allCases.enumerated()), id: \.offset) { idx, kind in
                Button("") { postSetKind(kind) }
                    .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: .command)
                    .opacity(0)
            }
        }
    }

    private func postSetKind(_ kind: SceneElementKind) {
        NotificationCenter.default.post(
            name: .penovaSetElementKind,
            object: nil,
            userInfo: ["kind": kind.rawValue]
        )
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

    /// The episode the export sheet should target — the currently
    /// selected scene's episode, falling back to the first episode of
    /// the first project. Picks the project's biggest episode if no
    /// selection so a fresh launch exports something meaningful.
    private var currentExportEpisode: Episode? {
        if let ep = selectedScene?.episode { return ep }
        guard let project = projects.first else { return nil }
        let episodes = project.activeEpisodesOrdered
        return episodes.max(by: { $0.scenes.count < $1.scenes.count })
            ?? episodes.first
    }

    /// The project the title-page editor should open against — the
    /// currently selected scene's project, or the first project.
    private var currentProject: Project? {
        selectedScene?.episode?.project ?? projects.first
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
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(PenovaColor.amber)
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Button(action: printCurrentProject) {
                Label("Print", systemImage: "printer")
            }
            .controlSize(.large)
            .keyboardShortcut("p", modifiers: .command)

            Menu {
                Button("Export PDF…") {
                    pendingExportFormat = .pdf
                    exportSheetVisible = true
                }
                Button("Export Final Draft (FDX)…") {
                    pendingExportFormat = .fdx
                    exportSheetVisible = true
                }
                Button("Export Fountain…") {
                    pendingExportFormat = .fountain
                    exportSheetVisible = true
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .controlSize(.large)
        }

        ToolbarItem(placement: .principal) {
            Picker("", selection: $viewMode) {
                ForEach(CenterViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleOnly)
            .controlSize(.large)
            .frame(width: 320)
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { focusMode.toggle() }) {
                Label("Focus Mode", systemImage: focusMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .controlSize(.large)
            .keyboardShortcut("f", modifiers: [.command, .control])
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { inspectorVisible.toggle() }) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .controlSize(.large)
            .keyboardShortcut("0", modifiers: [.command, .option])
        }
    }

    // MARK: - Center pane (editor / cards / outline)

    @ViewBuilder
    private var centerPane: some View {
        if let group = activeSmart {
            SmartGroupPane(
                group: group,
                projects: projects,
                onSelectScene: { scene in
                    selectedScene = scene
                    activeSmart = nil
                    viewMode = .editor
                }
            )
        } else {
            switch viewMode {
            case .editor:
                ScriptEditorPane(scene: selectedScene)
            case .cards:
                IndexCardsPane(
                    projects: projects,
                    selectedScene: $selectedScene,
                    onOpenScene: { scene in
                        selectedScene = scene
                        viewMode = .editor
                    }
                )
            case .outline:
                OutlinePane(
                    projects: projects,
                    selectedScene: $selectedScene,
                    onOpenScene: { scene in
                        selectedScene = scene
                        viewMode = .editor
                    }
                )
            }
        }
    }

    // MARK: - Focus mode pill

    private var focusPill: some View {
        HStack(spacing: 14) {
            Image(systemName: "scope")
                .foregroundStyle(PenovaColor.amber)
                .font(.system(size: 13))
            Text("Focus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PenovaColor.snow)
            Text("·").foregroundStyle(PenovaColor.ink5)
            Text(pageEstimate)
                .font(.custom("RobotoMono-Medium", size: 13))
                .foregroundStyle(PenovaColor.snow)
            Text("·").foregroundStyle(PenovaColor.ink5)
            Button(action: { focusMode = false }) {
                HStack(spacing: 8) {
                    Text("Exit")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PenovaColor.snow2)
                    Text("Esc")
                        .font(.custom("RobotoMono-Medium", size: 11))
                        .foregroundStyle(PenovaColor.snow3)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(PenovaColor.ink3)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(PenovaColor.ink4, lineWidth: 1))
        .fixedSize()
        .padding(.bottom, 28)
    }

    private func newScene() {
        // Use the currently-selected scene's episode if possible; otherwise
        // the first episode of the first project.
        let targetEpisode: Episode? = selectedScene?.episode
            ?? projects.first?.activeEpisodesOrdered.first
        guard let episode = targetEpisode else {
            // No project yet — open the new-project sheet instead
            newProjectVisible = true
            return
        }
        let nextOrder = (episode.scenes.map(\.order).max() ?? -1) + 1
        let scene = ScriptScene(
            locationName: "NEW LOCATION",
            location: .interior,
            time: .day,
            order: nextOrder
        )
        scene.episode = episode
        context.insert(scene)
        // Starter action element so the editor focuses on something
        // typable as soon as the writer lands.
        let starter = SceneElement(kind: .action, text: "", order: 0)
        starter.scene = scene
        context.insert(starter)
        try? context.save()
        selectedScene = scene
        activeSmart = nil
        viewMode = .editor
        PenovaLog.editor.info("New scene inserted in episode '\(episode.title, privacy: .public)' at order \(nextOrder)")
    }

    /// ⌘P: render the current project to a temporary PDF and open it
    /// in Preview for the user to print/save. We can't drive the
    /// system print panel headlessly, so this is the pragmatic v1 flow.
    private func printCurrentProject() {
        guard let project = selectedScene?.episode?.project ?? projects.first else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Penova-\(project.title)-\(UUID().uuidString.prefix(6)).pdf")
        do {
            try ScreenplayPDFRenderer.render(project: project, to: url)
            NSWorkspace.shared.open(url)
            PenovaLog.export.info("Print: opened PDF in Preview at \(url.lastPathComponent, privacy: .public)")
        } catch {
            PenovaLog.export.error("Print failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Sheets and overlays

private struct SheetsAndOverlays: ViewModifier {
    @Binding var searchVisible: Bool
    @Binding var titlePageVisible: Bool
    @Binding var exportVisible: Bool
    @Binding var newProjectVisible: Bool
    let projects: [Project]
    let exportTarget: Episode?
    let titlePageProject: Project?
    let onSelectScene: (ScriptScene) -> Void
    let onProjectCreated: (Project) -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if searchVisible {
                    MacSearchOverlay(
                        isVisible: $searchVisible,
                        projects: projects,
                        onSelectScene: onSelectScene
                    )
                }
            }
            .sheet(isPresented: $titlePageVisible) {
                if let project = titlePageProject {
                    TitlePageEditorSheet(project: project)
                        .frame(width: 920, height: 540)
                }
            }
            .sheet(isPresented: $exportVisible) {
                if let episode = exportTarget {
                    MacExportSheet(episode: episode)
                        .frame(width: 600)
                }
            }
            .sheet(isPresented: $newProjectVisible) {
                MacNewProjectSheet(onCreated: onProjectCreated)
            }
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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(PenovaColor.ink1)
        .overlay(Rectangle().fill(PenovaColor.ink4).frame(height: 1), alignment: .top)
    }
}
