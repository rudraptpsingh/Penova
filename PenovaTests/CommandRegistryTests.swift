//
//  CommandRegistryTests.swift
//  PenovaTests
//
//  Pins the registry's contract:
//   • register / unregister / run by id
//   • search returns scored results, ranked by total score desc
//   • title hits weigh more than aliases > keywords
//   • empty query returns every command (score 0)
//   • result limit is respected
//   • allGrouped() preserves group order and sorts within
//

import Testing
import Foundation
@testable import PenovaKit

@MainActor
@Suite struct CommandRegistryTests {

    private func makeRegistry() -> CommandRegistry {
        let r = CommandRegistry()
        r.register(
            PenovaCommand(
                id: "rename-character",
                title: "Rename character…",
                group: .editing,
                aliases: ["change name"],
                keywords: ["rename", "edit"],
                shortcut: PenovaCommandShortcut([.command], "R")
            ),
            handler: {}
        )
        r.register(
            PenovaCommand(
                id: "reorder-scene",
                title: "Reorder scene",
                group: .editing,
                keywords: ["move", "shift"]
            ),
            handler: {}
        )
        r.register(
            PenovaCommand(
                id: "switch-cards",
                title: "Switch to Index Cards",
                group: .views,
                aliases: ["index cards", "board"],
                shortcut: PenovaCommandShortcut([.command], "2")
            ),
            handler: {}
        )
        r.register(
            PenovaCommand(
                id: "save-revision",
                title: "Save revision",
                subtitle: "Advance to the next colour",
                group: .production,
                aliases: ["pink", "yellow", "blue"],
                shortcut: PenovaCommandShortcut([.shift, .command], "R")
            ),
            handler: {}
        )
        return r
    }

    // MARK: - Registration

    @Test func registerAddsCommand() {
        let r = CommandRegistry()
        #expect(r.commands.isEmpty)
        r.register(
            PenovaCommand(id: "x", title: "X", group: .editing),
            handler: {}
        )
        #expect(r.commands.count == 1)
        #expect(r.commands.first?.id == "x")
    }

    @Test func registerSameIdReplacesNotDuplicates() {
        let r = CommandRegistry()
        r.register(PenovaCommand(id: "x", title: "Old", group: .editing), handler: {})
        r.register(PenovaCommand(id: "x", title: "New", group: .editing), handler: {})
        #expect(r.commands.count == 1)
        #expect(r.commands.first?.title == "New")
    }

    @Test func unregisterRemoves() {
        let r = makeRegistry()
        let before = r.commands.count
        r.unregister(id: "rename-character")
        #expect(r.commands.count == before - 1)
        #expect(r.commands.first(where: { $0.id == "rename-character" }) == nil)
    }

    // MARK: - Run

    @Test func runInvokesHandler() {
        let r = CommandRegistry()
        var calls = 0
        r.register(PenovaCommand(id: "x", title: "X", group: .editing)) {
            calls += 1
        }
        #expect(r.run(id: "x") == true)
        #expect(calls == 1)
    }

    @Test func runUnknownIdNoOps() {
        let r = CommandRegistry()
        #expect(r.run(id: "missing") == false)
    }

    // MARK: - Search ranking

    @Test func searchEmptyQueryReturnsAllAtZeroScore() {
        let r = makeRegistry()
        let results = r.search("")
        #expect(results.count == r.commands.count)
        #expect(results.allSatisfy { $0.score == 0 })
    }

    @Test func searchRanksTitleHitsAboveAliasOnlyMatches() {
        let r = makeRegistry()
        // Query "rena" hits "Rename character…" by title strongly.
        // The aliases "change name" and keywords ["rename","edit"] also
        // contain "rena" — but title score should dominate.
        let results = r.search("rena")
        #expect(results.first?.command.id == "rename-character")
    }

    @Test func searchPicksTopScoringCommand() {
        let r = makeRegistry()
        let results = r.search("save")
        // "Save revision" has 'save' as the title prefix → should win.
        #expect(results.first?.command.id == "save-revision")
    }

    @Test func searchMatchesViaAlias() {
        let r = makeRegistry()
        // "Pink" appears only in the save-revision command's alias list.
        let results = r.search("pink")
        #expect(results.contains(where: { $0.command.id == "save-revision" }))
    }

    @Test func searchExcludesNonMatches() {
        let r = makeRegistry()
        let results = r.search("zxqwerty")
        #expect(results.isEmpty)
    }

    @Test func searchRespectsLimit() {
        let r = makeRegistry()
        let limited = r.search("e", limit: 2)
        #expect(limited.count <= 2)
    }

    @Test func searchReturnsMatchedIndicesForTitleHighlight() {
        let r = makeRegistry()
        let results = r.search("rena")
        let top = results.first
        #expect(top?.matchedIndices == [0, 1, 2, 3])
    }

    // MARK: - Grouping

    @Test func allGroupedPreservesGroupOrder() {
        let r = makeRegistry()
        let grouped = r.allGrouped()
        let groupOrder = grouped.map(\.group)
        // Per PenovaCommandGroup.sortOrder: views (2) < editing (3) <
        // production (4). The fixture registers commands in all three
        // groups so all three indices should resolve.
        let editingIdx = groupOrder.firstIndex(of: .editing)
        let viewsIdx = groupOrder.firstIndex(of: .views)
        let productionIdx = groupOrder.firstIndex(of: .production)
        #expect(editingIdx != nil)
        #expect(viewsIdx != nil)
        #expect(productionIdx != nil)
        #expect(viewsIdx! < editingIdx!)
        #expect(editingIdx! < productionIdx!)
    }

    @Test func searchGroupedSplitsByGroup() {
        let r = makeRegistry()
        let results = r.search("e")
        let grouped = CommandSearch.grouped(results)
        // Each group bucket should contain only commands of that group.
        for (group, items) in grouped {
            #expect(items.allSatisfy { $0.command.group == group })
        }
    }

    // MARK: - Shortcut display

    @Test func shortcutDisplayString() {
        let s = PenovaCommandShortcut([.shift, .command], "R")
        #expect(s.displayString == "⇧⌘R")
    }

    @Test func shortcutDisplayTokens() {
        let s = PenovaCommandShortcut([.command], "K")
        #expect(s.displayTokens == ["⌘", "K"])
    }
}
