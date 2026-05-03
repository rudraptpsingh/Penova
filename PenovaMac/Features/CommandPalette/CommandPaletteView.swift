//
//  CommandPaletteView.swift
//  Penova for Mac
//
//  ⌘K modal overlay. Linear / Raycast flavour: dim the editor, float
//  a 640pt-wide card centred near the top of the window, prompt the
//  user to type, render ranked results grouped by section.
//
//  Wires up the CommandRegistry from PenovaKit. Apps register their
//  actions once at launch (LibraryWindowView does this) and the
//  palette is a thin discovery surface — it never knows what any
//  command does, only how to find and dispatch one by id.
//
//  Keyboard model:
//    • ⌘K        — show the palette (handled by parent view)
//    • esc       — hide
//    • ↑↓        — move selection
//    • ↵         — run the selected command, hide
//    • text      — filter
//
//  Visual rules respect the design system:
//    • One accent (amber). Never decorative.
//    • Three radii: 8 (chip), 12 (card), 9999 (avatar).
//    • Modal-with-elevation is the one place this app uses elevation.
//

import SwiftUI
import SwiftData
import PenovaKit

struct CommandPaletteView: View {

    @ObservedObject var registry: CommandRegistry
    @Binding var visible: Bool

    @State private var query: String = ""
    @State private var selectedID: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            backdrop
            paletteCard
                .frame(width: 640)
                .frame(maxHeight: 540)
                .padding(.top, 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            inputFocused = true
            updateSelectionToFirstResult()
        }
        .onChange(of: query) { _, _ in
            updateSelectionToFirstResult()
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        Color.black.opacity(0.78)
            .ignoresSafeArea()
            .onTapGesture { dismiss() }
    }

    // MARK: - Card

    private var paletteCard: some View {
        VStack(spacing: 0) {
            inputBar
            Divider().background(PenovaColor.ink4)
            resultsList
            Divider().background(PenovaColor.ink4)
            footerHints
        }
        .background(PenovaColor.ink2)
        .overlay(
            RoundedRectangle(cornerRadius: PenovaRadius.md)
                .strokeBorder(PenovaColor.ink5, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        .shadow(color: .black.opacity(0.7), radius: 30, x: 0, y: 12)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: PenovaSpace.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PenovaColor.snow4)
                .frame(width: 16)

            TextField(
                "Type a command, scene, character, or page…",
                text: $query
            )
            .textFieldStyle(.plain)
            .font(PenovaFont.title)
            .foregroundStyle(PenovaColor.snow)
            .focused($inputFocused)
            .onSubmit { runSelected() }
            .onKeyPress(.escape) { dismiss(); return .handled }
            .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
            .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }

            Text("esc to close")
                .font(.custom("RobotoMono-Regular", size: 10))
                .foregroundStyle(PenovaColor.snow4)
        }
        .padding(.horizontal, PenovaSpace.l)
        .padding(.vertical, PenovaSpace.m)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedResults, id: \.group) { entry in
                        sectionHeader(entry.group, count: entry.items.count)
                        ForEach(entry.items, id: \.id) { result in
                            row(for: result)
                                .id(result.id)
                        }
                    }
                    if groupedResults.isEmpty {
                        emptyState
                    }
                }
            }
            .onChange(of: selectedID) { _, new in
                guard let new else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .frame(maxHeight: 400)
        }
    }

    private func sectionHeader(_ group: PenovaCommandGroup, count: Int) -> some View {
        HStack {
            Text(group.display.uppercased())
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelCaps)
            Spacer()
            Text("\(count)")
                .font(.custom("RobotoMono-Regular", size: 10))
        }
        .foregroundStyle(PenovaColor.snow4)
        .padding(.horizontal, PenovaSpace.l)
        .padding(.top, PenovaSpace.sm)
        .padding(.bottom, PenovaSpace.xs)
    }

    private func row(for result: CommandSearch.Result) -> some View {
        let isActive = result.id == selectedID
        return Button {
            run(commandID: result.id)
        } label: {
            HStack(spacing: PenovaSpace.sm) {
                Rectangle()
                    .fill(isActive ? PenovaColor.amber : Color.clear)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 2) {
                    titleText(for: result)
                    if let sub = result.command.subtitle {
                        Text(sub)
                            .font(.custom("RobotoMono-Regular", size: 10))
                            .foregroundStyle(PenovaColor.snow4)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let shortcut = result.command.shortcut {
                    shortcutTokens(shortcut)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, PenovaSpace.l - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive
                ? PenovaColor.amber.opacity(0.08)
                : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selectedID = result.id }
        }
    }

    /// Title with matched chars rendered in amber. Falls back to plain
    /// title when no matched indices come back (empty query case).
    private func titleText(for result: CommandSearch.Result) -> some View {
        let title = result.command.title
        if result.matchedIndices.isEmpty {
            return Text(title)
                .font(PenovaFont.bodyMedium)
                .foregroundStyle(PenovaColor.snow)
        }
        var attr = AttributedString(title)
        let indices = Set(result.matchedIndices)
        for (i, ch) in title.enumerated() {
            // Skip non-character indices (multi-scalar graphemes are
            // counted by `String.Index` walking — this assumes ASCII-
            // dominant titles, which our shipped commands are).
            _ = ch
            if indices.contains(i) {
                let lower = attr.characters.index(
                    attr.startIndex, offsetBy: i
                )
                let upper = attr.characters.index(after: lower)
                attr[lower..<upper].foregroundColor = PenovaColor.amber
                attr[lower..<upper].font = PenovaFont.bodyMedium.weight(.semibold)
            }
        }
        return Text(attr)
            .font(PenovaFont.bodyMedium)
            .foregroundStyle(PenovaColor.snow)
    }

    private func shortcutTokens(_ shortcut: PenovaCommandShortcut) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(shortcut.displayTokens.enumerated()), id: \.offset) { _, token in
                Text(token)
                    .font(.custom("RobotoMono-Regular", size: 10))
                    .foregroundStyle(PenovaColor.snow3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PenovaColor.ink3)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(PenovaColor.ink4, lineWidth: 1)
                    )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: PenovaSpace.s) {
            Text("Nothing matches")
                .font(PenovaFont.bodyMedium)
                .foregroundStyle(PenovaColor.snow3)
            Text("Try a shorter query or a synonym.")
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow4)
        }
        .padding(.vertical, PenovaSpace.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footerHints: some View {
        HStack(spacing: PenovaSpace.l) {
            footerHint("↑↓", "navigate")
            footerHint("↵", "select")
            footerHint("esc", "close")
            Spacer()
            Text("one keystroke. the whole app.")
                .font(.custom("RobotoMono-Regular", size: 10))
                .foregroundStyle(PenovaColor.snow4)
        }
        .padding(.horizontal, PenovaSpace.l)
        .padding(.vertical, PenovaSpace.sm)
        .background(PenovaColor.ink1)
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.custom("RobotoMono-Regular", size: 10))
                .foregroundStyle(PenovaColor.snow3)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(PenovaColor.ink3)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.custom("RobotoMono-Regular", size: 10))
                .foregroundStyle(PenovaColor.snow4)
        }
    }

    // MARK: - Behaviour

    private var groupedResults: [(group: PenovaCommandGroup, items: [CommandSearch.Result])] {
        if query.isEmpty {
            // Empty query — show every registered command grouped, score 0.
            return registry.allGrouped().map { entry in
                let results = entry.items.map { c in
                    CommandSearch.Result(
                        command: c,
                        score: 0,
                        matchedIndices: []
                    )
                }
                return (entry.group, results)
            }
        }
        let scored = registry.search(query, limit: 50)
        return CommandSearch.grouped(scored)
    }

    private var flatResultIDs: [String] {
        groupedResults.flatMap { $0.items.map(\.id) }
    }

    private func updateSelectionToFirstResult() {
        selectedID = flatResultIDs.first
    }

    private func moveSelection(by offset: Int) {
        let ids = flatResultIDs
        guard !ids.isEmpty else { selectedID = nil; return }
        let current = selectedID.flatMap(ids.firstIndex(of:)) ?? -1
        let next = max(0, min(ids.count - 1, current + offset))
        selectedID = ids[next]
    }

    private func runSelected() {
        guard let selectedID else { return }
        run(commandID: selectedID)
    }

    private func run(commandID: String) {
        _ = registry.run(id: commandID)
        dismiss()
    }

    private func dismiss() {
        visible = false
        query = ""
        selectedID = nil
        inputFocused = false
    }
}

// MARK: - Preview
//
// Open this file in Xcode and the preview renders the palette with
// the realistic mockup payload — a CommandRegistry pre-populated with
// the production / navigation / view actions the LibraryWindowView
// will register at launch. Visual verification surface; no SwiftData
// container needed.

#Preview("Empty query — all sections") {
    let registry = CommandRegistry()
    seedDemoCommands(registry)
    return CommandPaletteView(registry: registry, visible: .constant(true))
        .frame(width: 1100, height: 700)
        .background(PenovaColor.ink0)
}

#Preview("Query: 'rena' — top hit highlighted") {
    let registry = CommandRegistry()
    seedDemoCommands(registry)
    let view = CommandPaletteView(registry: registry, visible: .constant(true))
    return view
        .frame(width: 1100, height: 700)
        .background(PenovaColor.ink0)
        .task {
            // Note: query state lives inside CommandPaletteView; can't
            // pre-fill from the preview without exposing it. The first
            // preview ("Empty query") covers the empty case; this
            // preview just renders the same UI with the same registry.
            // Stub kept for documentation symmetry.
        }
}

@MainActor
private func seedDemoCommands(_ r: CommandRegistry) {
    r.register(
        PenovaCommand(
            id: "rename-character",
            title: "Rename character…",
            subtitle: "Atomic, undo-safe — uses CharacterRename service",
            group: .editing,
            aliases: ["change name"],
            keywords: ["rename", "edit"],
            shortcut: PenovaCommandShortcut([.command], "R")
        ),
        handler: {}
    )
    r.register(
        PenovaCommand(
            id: "save-revision",
            title: "Save Pink revision",
            subtitle: "Advance Blue → Pink, snapshot Fountain",
            group: .production,
            aliases: ["pink", "yellow", "blue"],
            keywords: ["color", "production"],
            shortcut: PenovaCommandShortcut([.shift, .command], "R")
        ),
        handler: {}
    )
    r.register(
        PenovaCommand(
            id: "lock-script",
            title: "Lock script for production",
            subtitle: "Freeze scene numbers — runs Project.lock()",
            group: .production,
            aliases: ["freeze"],
            shortcut: PenovaCommandShortcut([.shift, .command], "L")
        ),
        handler: {}
    )
    r.register(
        PenovaCommand(
            id: "view-cards",
            title: "Switch to Index Cards",
            subtitle: "CenterViewMode = .cards",
            group: .views,
            aliases: ["board", "cards"],
            shortcut: PenovaCommandShortcut([.command], "2")
        ),
        handler: {}
    )
    r.register(
        PenovaCommand(
            id: "view-outline",
            title: "Switch to Outline",
            group: .views,
            shortcut: PenovaCommandShortcut([.command], "3")
        ),
        handler: {}
    )
    r.register(
        PenovaCommand(
            id: "go-to-scene",
            title: "Go to scene…",
            subtitle: "Jump by scene heading or page number",
            group: .navigation,
            shortcut: PenovaCommandShortcut([.command], "G")
        ),
        handler: {}
    )
    r.register(
        PenovaCommand(
            id: "export-pdf",
            title: "Export as PDF",
            subtitle: "A4 Courier 12pt — WGA format",
            group: .production,
            keywords: ["share", "send"],
            shortcut: PenovaCommandShortcut([.command], "E")
        ),
        handler: {}
    )
    r.register(
        PenovaCommand(
            id: "open-search",
            title: "Search the script",
            group: .navigation,
            shortcut: PenovaCommandShortcut([.command], "F")
        ),
        handler: {}
    )
}
