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
    @State private var reportsSheetVisible: Bool = false
    @State private var newProjectVisible: Bool = false
    @State private var pendingExportFormat: MacExportFormat = .pdf
    @State private var lockConfirmVisible: Bool = false
    @State private var unlockConfirmVisible: Bool = false
    @State private var pendingSceneDelete: ScriptScene?
    @State private var renamingProject: Project?
    @State private var renameDraft: String = ""
    @State private var pendingProjectTrash: Project?
    @State private var pendingProjectDeleteForever: Project?
    @State private var paletteVisible: Bool = false
    @StateObject private var commandRegistry = CommandRegistry()
    @State private var saveRevisionSheetVisible: Bool = false
    @StateObject private var sprintSession = SprintSession()

    var body: some View {
        baseShell
            .accessibilityIdentifier(A11yID.libraryWindow)
            .overlay {
                if paletteVisible {
                    CommandPaletteView(
                        registry: commandRegistry,
                        visible: $paletteVisible
                    )
                    .transition(.opacity)
                }
            }
            .onAppear { registerStarterCommands() }
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
            .sheet(isPresented: $reportsSheetVisible) {
                if let project = currentProject {
                    MacReportsSheet(project: project)
                }
            }
            .sheet(isPresented: $saveRevisionSheetVisible) {
                if let project = currentProject {
                    SaveRevisionSheet(project: project) { _ in
                        // Saved — nothing else to do; SaveRevisionService
                        // already persisted the row and bumped the
                        // project's updatedAt.
                    } onCancel: {
                        // Cancel — nothing to clean up either.
                    }
                }
            }
            .alert("Lock script for production?", isPresented: $lockConfirmVisible) {
                Button("Cancel", role: .cancel) {}
                Button("Lock") { lockCurrentProject() }
            } message: {
                Text("Scene numbers freeze at their current values. Adding, deleting, or reordering scenes after this won't renumber survivors. You can unlock anytime.")
            }
            .alert("Unlock script?", isPresented: $unlockConfirmVisible) {
                Button("Cancel", role: .cancel) {}
                Button("Unlock", role: .destructive) { unlockCurrentProject() }
            } message: {
                Text("Scene numbers will resume tracking the live scene order. Any production-stage references to the locked numbers will be lost.")
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
                Text("This removes “\(pendingSceneDelete?.heading ?? "")” and every element in it. This can't be undone.")
            }
            .modifier(ProjectManagementAlerts(
                pendingProjectTrash: $pendingProjectTrash,
                pendingProjectDeleteForever: $pendingProjectDeleteForever,
                renamingProject: $renamingProject,
                onConfirmTrash: { confirmTrash() },
                onConfirmDeleteForever: { confirmDeleteForever() },
                renameSheet: { renameProjectSheet }
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
            .onReceive(NotificationCenter.default.publisher(for: .penovaShowReports)) { _ in
                reportsSheetVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .penovaLockScript)) { _ in
                if currentProject?.locked == false {
                    lockConfirmVisible = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .penovaUnlockScript)) { _ in
                if currentProject?.locked == true {
                    unlockConfirmVisible = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .penovaStartNewRevision)) { _ in
                startNewRevisionOnCurrentProject()
            }
    }

    private var baseShell: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                LibrarySidebar(
                    projects: projects,
                    selectedScene: $selectedScene,
                    activeSmart: $activeSmart,
                    onRenameProject: { startRename(project: $0) },
                    onArchiveProject: { archive(project: $0) },
                    onTrashProject: { requestTrash(project: $0) },
                    onRestoreProject: { restore(project: $0) }
                )
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            } detail: {
                HStack(spacing: 0) {
                    centerPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if inspectorVisible && !focusMode {
                        Divider().background(PenovaColor.ink4)
                        SceneInspector(
                            scene: selectedScene,
                            onRequestDelete: { scene in
                                pendingSceneDelete = scene
                            }
                        )
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
            // ⌘K — Command Palette. Lives in the same hidden block as
            // the other shortcuts so it lands in the window's responder
            // chain reliably (a separate .background() can be pruned
            // by SwiftUI in some layouts).
            Button("") { paletteVisible.toggle() }
                .keyboardShortcut("k", modifiers: .command)
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

    // MARK: - Command palette

    /// Register the first batch of palette commands. Mirrors the
    /// shortcuts already exposed in `hiddenShortcuts` and the
    /// CommandGroup menu blocks. Each command resolves to a small
    /// closure that does the same thing the existing menu item does;
    /// this keeps the palette and the menus in step.
    ///
    /// Idempotent — `register(_:handler:)` is keyed by id, so if the
    /// view appears twice in a session we don't end up with duplicates.
    private func registerStarterCommands() {
        commandRegistry.register(
            PenovaCommand(
                id: "view-editor",
                title: "Switch to Editor",
                group: .views,
                shortcut: PenovaCommandShortcut([.command], "1")
            ),
            handler: { viewMode = .editor }
        )
        commandRegistry.register(
            PenovaCommand(
                id: "view-cards",
                title: "Switch to Index Cards",
                group: .views,
                aliases: ["board", "cards"],
                shortcut: PenovaCommandShortcut([.command], "2")
            ),
            handler: { viewMode = .cards }
        )
        commandRegistry.register(
            PenovaCommand(
                id: "view-outline",
                title: "Switch to Outline",
                group: .views,
                shortcut: PenovaCommandShortcut([.command], "3")
            ),
            handler: { viewMode = .outline }
        )
        commandRegistry.register(
            PenovaCommand(
                id: "open-search",
                title: "Search the script",
                subtitle: "Find scenes, characters, dialogue",
                group: .navigation,
                shortcut: PenovaCommandShortcut([.command], "F")
            ),
            handler: { searchVisible = true }
        )
        commandRegistry.register(
            PenovaCommand(
                id: "open-title-page",
                title: "Edit title page",
                group: .editing,
                shortcut: PenovaCommandShortcut([.shift, .command], "T")
            ),
            handler: { titlePageEditorVisible = true }
        )
        commandRegistry.register(
            PenovaCommand(
                id: "export",
                title: "Export…",
                subtitle: "PDF, FDX, or Fountain",
                group: .production,
                aliases: ["share", "send"],
                shortcut: PenovaCommandShortcut([.command], "E")
            ),
            handler: { exportSheetVisible = true }
        )
        commandRegistry.register(
            PenovaCommand(
                id: "open-reports",
                title: "Production reports",
                subtitle: "Scene + character counts",
                group: .production,
                shortcut: PenovaCommandShortcut([.shift, .command], "R")
            ),
            handler: { reportsSheetVisible = true }
        )
        commandRegistry.register(
            PenovaCommand(
                id: "lock-script",
                title: "Lock script for production",
                subtitle: "Freeze scene numbers — Project.lock()",
                group: .production,
                aliases: ["freeze"]
            ),
            handler: {
                if currentProject?.locked == false {
                    lockConfirmVisible = true
                }
            }
        )
        commandRegistry.register(
            PenovaCommand(
                id: "unlock-script",
                title: "Unlock script",
                subtitle: "Resume live scene numbering",
                group: .production
            ),
            handler: {
                if currentProject?.locked == true {
                    unlockConfirmVisible = true
                }
            }
        )
        commandRegistry.register(
            PenovaCommand(
                id: "new-scene",
                title: "New scene",
                group: .editing,
                shortcut: PenovaCommandShortcut([.shift, .command], "N")
            ),
            handler: { newScene() }
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

    /// Total word count across the current project's scene elements.
    /// Used by the SprintChip to compute the "words added during this
    /// sprint" delta. Cheap: walks element text and splits on
    /// whitespace; no SwiftData query beyond what's already loaded.
    private var totalWordCount: Int {
        guard let project = currentProject else { return 0 }
        var total = 0
        for ep in project.activeEpisodesOrdered {
            for scene in ep.scenesOrdered {
                for el in scene.elements {
                    total += el.text
                        .split { $0.isWhitespace || $0.isNewline }
                        .filter { !$0.isEmpty }
                        .count
                }
            }
        }
        return total
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

        ToolbarItem(placement: .secondaryAction) {
            SprintChip(
                session: sprintSession,
                currentWordCount: { totalWordCount }
            )
            .onChange(of: pageEstimate) { _, _ in
                // Cheap way to nudge the chip's word count: piggy-back
                // on the page estimate which already updates on every
                // edit. Avoids adding another SwiftData query.
                sprintSession.update(currentWords: totalWordCount)
            }
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Button(action: printCurrentProject) {
                Label("Print", systemImage: "printer")
            }
            .controlSize(.large)
            .keyboardShortcut("p", modifiers: .command)

            Button(action: { reportsSheetVisible = true }) {
                Label("Reports", systemImage: "tablecells")
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Scene, location, and cast breakdown reports (⇧⌘R)")

            // Lock / Unlock script for production. Toggle reflects
            // current `Project.locked` state for the active project.
            Menu {
                if currentProject?.locked == true {
                    Button("Unlock script") { unlockConfirmVisible = true }
                } else {
                    Button("Lock script…") { lockConfirmVisible = true }
                }
            } label: {
                Label(
                    currentProject?.locked == true ? "Locked" : "Lock",
                    systemImage: currentProject?.locked == true ? "lock.fill" : "lock"
                )
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.large)
            .help("Freeze scene numbers for production. Unlock to resume live numbering.")

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
                    },
                    onRequestDelete: { pendingSceneDelete = $0 }
                )
            case .outline:
                OutlinePane(
                    projects: projects,
                    selectedScene: $selectedScene,
                    onOpenScene: { scene in
                        selectedScene = scene
                        viewMode = .editor
                    },
                    onRequestDelete: { pendingSceneDelete = $0 }
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

    /// Apply a pending scene delete (set by the inspector / outline /
    /// index-cards context menu). Snaps the editor to the next-best
    /// surviving scene in the same episode so the user isn't left
    /// staring at an empty editor pane.
    private func deletePendingScene() {
        guard let scene = pendingSceneDelete else { return }
        let parentEpisode = scene.episode
        let siblings = parentEpisode?.scenesOrdered ?? []
        let idx = siblings.firstIndex(where: { $0.id == scene.id })
        let neighbour: ScriptScene? = {
            guard let idx else { return siblings.first(where: { $0.id != scene.id }) }
            // Prefer the next sibling, else the previous, else nil.
            if idx + 1 < siblings.count { return siblings[idx + 1] }
            if idx - 1 >= 0 { return siblings[idx - 1] }
            return nil
        }()
        context.delete(scene)
        try? context.save()
        if selectedScene?.id == scene.id {
            selectedScene = neighbour
        }
        pendingSceneDelete = nil
    }

    private func lockCurrentProject() {
        guard let p = currentProject else { return }
        p.lock()
        try? context.save()
    }

    private func unlockCurrentProject() {
        guard let p = currentProject else { return }
        p.unlock()
        try? context.save()
    }

    /// Snapshot the project state into a new Revision row, advancing
    /// the WGA color cycle by one. Triggered from the Production
    /// menu's "Start New Revision…" command (⌘⌥R). Subsequent edits
    /// will stamp `lastRevisedRevisionID` on this revision so the PDF
    /// renderer flags the changed pages.
    /// Show the SaveRevisionSheet. Replaces the previous inline save
    /// path — the sheet itself routes through SaveRevisionService to
    /// snapshot Fountain, build the Revision row, and advance the
    /// colour. Keeps menu shortcut behaviour unchanged but adds an
    /// explicit confirm step + optional note before persisting.
    private func startNewRevisionOnCurrentProject() {
        guard currentProject != nil else { return }
        saveRevisionSheetVisible = true
    }

    // MARK: - Project management (Mac)

    private func startRename(project: Project) {
        renamingProject = project
        renameDraft = project.title
    }

    private func commitRename() {
        guard let project = renamingProject else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.title = trimmed
        project.updatedAt = .now
        try? context.save()
        renamingProject = nil
    }

    private func archive(project: Project) {
        project.status = (project.status == .archived) ? .active : .archived
        project.updatedAt = .now
        try? context.save()
    }

    private func requestTrash(project: Project) {
        if project.status == .trashed {
            pendingProjectDeleteForever = project
        } else {
            pendingProjectTrash = project
        }
    }

    private func confirmTrash() {
        guard let project = pendingProjectTrash else { return }
        project.status = .trashed
        project.trashedAt = .now
        project.updatedAt = .now
        try? context.save()
        if selectedScene?.episode?.project?.id == project.id {
            selectedScene = projects
                .filter { $0.status == .active && $0.id != project.id }
                .flatMap(\.activeEpisodesOrdered)
                .flatMap(\.scenesOrdered)
                .first
        }
        pendingProjectTrash = nil
    }

    private func confirmDeleteForever() {
        guard let project = pendingProjectDeleteForever else { return }
        if selectedScene?.episode?.project?.id == project.id {
            selectedScene = projects
                .filter { $0.id != project.id }
                .flatMap(\.activeEpisodesOrdered)
                .flatMap(\.scenesOrdered)
                .first
        }
        context.delete(project)
        try? context.save()
        pendingProjectDeleteForever = nil
    }

    private func restore(project: Project) {
        project.status = .active
        project.trashedAt = nil
        project.updatedAt = .now
        try? context.save()
    }

    @ViewBuilder
    private var renameProjectSheet: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.m) {
            Text("Rename project")
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow)
            TextField("Project name", text: $renameDraft)
                .textFieldStyle(.plain)
                .font(PenovaFont.body)
                .padding(PenovaSpace.sm)
                .background(PenovaColor.ink3)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                .foregroundStyle(PenovaColor.snow)
                .onSubmit { commitRename() }

            HStack {
                Spacer()
                Button("Cancel") { renamingProject = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { commitRename() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(PenovaColor.amber)
                    .disabled(
                        renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
            }
        }
        .padding(PenovaSpace.l)
        .frame(width: 420)
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

// MARK: - Project management alerts modifier
//
// Extracted from LibraryWindowView.body to keep the type-checker
// happy. Three modifiers deep was tipping Swift's expression
// inference timeout. Each ViewModifier you add costs the type-
// checker; pulling these into a struct with a single body avoids
// inference of the parent's chain.

private struct ProjectManagementAlerts<RenameContent: View>: ViewModifier {
    @Binding var pendingProjectTrash: Project?
    @Binding var pendingProjectDeleteForever: Project?
    @Binding var renamingProject: Project?
    let onConfirmTrash: () -> Void
    let onConfirmDeleteForever: () -> Void
    @ViewBuilder let renameSheet: () -> RenameContent

    func body(content: Content) -> some View {
        content
            .alert(
                "Move \"\(pendingProjectTrash?.title ?? "")\" to Trash?",
                isPresented: Binding(
                    get: { pendingProjectTrash != nil },
                    set: { if !$0 { pendingProjectTrash = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingProjectTrash = nil }
                Button("Move to Trash", role: .destructive) { onConfirmTrash() }
            } message: {
                Text("The project disappears from the sidebar. Toggle \"Show archived & trash\" at the bottom to restore or delete forever.")
            }
            .alert(
                "Delete \"\(pendingProjectDeleteForever?.title ?? "")\" forever?",
                isPresented: Binding(
                    get: { pendingProjectDeleteForever != nil },
                    set: { if !$0 { pendingProjectDeleteForever = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingProjectDeleteForever = nil }
                Button("Delete forever", role: .destructive) { onConfirmDeleteForever() }
            } message: {
                Text("Removes the project and every episode, scene, and character it contains. This can't be undone.")
            }
            .sheet(isPresented: Binding(
                get: { renamingProject != nil },
                set: { if !$0 { renamingProject = nil } }
            )) {
                renameSheet()
            }
    }
}
