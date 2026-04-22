//
//  ReorderAndStatusTests.swift
//  PenovaTests
//
//  Coverage for ordering helpers (`scenesOrdered`, `elementsOrdered`,
//  `activeEpisodesOrdered`) plus Project status transitions and their
//  effect on relationships / query filters.
//

import Testing
import Foundation
import SwiftData
@testable import Penova

@MainActor
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
        configurations: config
    )
}

@MainActor
@Suite struct ReorderAndStatusTests {

    // MARK: - Ordering helpers

    @Test func scenesOrderedReturnsByOrderAscending() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)

        // Insert in non-sorted order to guarantee we're testing the sort.
        let s2 = ScriptScene(locationName: "TWO", order: 2); s2.episode = ep; ep.scenes.append(s2); ctx.insert(s2)
        let s0 = ScriptScene(locationName: "ZERO", order: 0); s0.episode = ep; ep.scenes.append(s0); ctx.insert(s0)
        let s1 = ScriptScene(locationName: "ONE", order: 1); s1.episode = ep; ep.scenes.append(s1); ctx.insert(s1)
        try ctx.save()

        let fetchedEp = try ctx.fetch(FetchDescriptor<Episode>()).first
        let ordered = fetchedEp?.scenesOrdered.map(\.locationName) ?? []
        #expect(ordered == ["ZERO", "ONE", "TWO"])
    }

    @Test func elementsOrderedReturnsByOrderAscending() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "S", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)

        let e2 = SceneElement(kind: .action, text: "two", order: 2); e2.scene = sc; sc.elements.append(e2); ctx.insert(e2)
        let e0 = SceneElement(kind: .action, text: "zero", order: 0); e0.scene = sc; sc.elements.append(e0); ctx.insert(e0)
        let e1 = SceneElement(kind: .action, text: "one", order: 1); e1.scene = sc; sc.elements.append(e1); ctx.insert(e1)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ScriptScene>()).first
        let texts = fetched?.elementsOrdered.map(\.text) ?? []
        #expect(texts == ["zero", "one", "two"])
    }

    /// Orders are not auto-renumbered on insert — gaps are preserved.
    @Test func elementsOrderedPreservesGaps() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "S", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)

        for i in 0..<3 {
            let e = SceneElement(kind: .action, text: "e\(i)", order: i)
            e.scene = sc; sc.elements.append(e); ctx.insert(e)
        }
        let gap = SceneElement(kind: .action, text: "gap", order: 5)
        gap.scene = sc; sc.elements.append(gap); ctx.insert(gap)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ScriptScene>()).first
        let orders = fetched?.elementsOrdered.map(\.order) ?? []
        #expect(orders == [0, 1, 2, 5])
    }

    @Test func swappingTwoSceneOrdersReordersList() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let a = ScriptScene(locationName: "A", order: 0); a.episode = ep; ep.scenes.append(a); ctx.insert(a)
        let b = ScriptScene(locationName: "B", order: 1); b.episode = ep; ep.scenes.append(b); ctx.insert(b)
        try ctx.save()

        #expect(ep.scenesOrdered.map(\.locationName) == ["A", "B"])

        // Swap
        a.order = 1
        b.order = 0
        try ctx.save()

        let fetchedEp = try ctx.fetch(FetchDescriptor<Episode>()).first
        #expect(fetchedEp?.scenesOrdered.map(\.locationName) == ["B", "A"])
    }

    @Test func bulkReverseOrderOfTenScenes() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)

        var scenes: [ScriptScene] = []
        for i in 0..<10 {
            let s = ScriptScene(locationName: "S\(i)", order: i)
            s.episode = ep; ep.scenes.append(s); ctx.insert(s)
            scenes.append(s)
        }
        try ctx.save()

        #expect(ep.scenesOrdered.map(\.locationName) == (0..<10).map { "S\($0)" })

        // Reverse
        for (i, s) in scenes.enumerated() {
            s.order = 9 - i
        }
        try ctx.save()

        let fetchedEp = try ctx.fetch(FetchDescriptor<Episode>()).first
        let names = fetchedEp?.scenesOrdered.map(\.locationName) ?? []
        #expect(names == (0..<10).reversed().map { "S\($0)" })
    }

    @Test func activeEpisodesOrderedSortsByOrder() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        // Insert out of order.
        let e2 = Episode(title: "Two", order: 2); e2.project = p; p.episodes.append(e2); ctx.insert(e2)
        let e0 = Episode(title: "Zero", order: 0); e0.project = p; p.episodes.append(e0); ctx.insert(e0)
        let e1 = Episode(title: "One", order: 1); e1.project = p; p.episodes.append(e1); ctx.insert(e1)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Project>()).first
        // Note: Project.activeEpisodesOrdered currently sorts by order but
        // does NOT filter by status — there is no status field on Episode
        // that maps to "active" (EpisodeStatus is draft/act1-done/etc).
        #expect(fetched?.activeEpisodesOrdered.map(\.title) == ["Zero", "One", "Two"])
    }

    // MARK: - Status transitions

    @Test func projectStatusRoundTripPreservesRelationships() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "S", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)
        let el = SceneElement(kind: .action, text: "hi", order: 0); el.scene = sc; sc.elements.append(el); ctx.insert(el)
        let ch = ScriptCharacter(name: "HERO"); ch.projects.append(p); p.characters.append(ch); ctx.insert(ch)
        try ctx.save()

        // active -> archived
        p.status = .archived
        p.updatedAt = .now
        try ctx.save()
        var fp = try ctx.fetch(FetchDescriptor<Project>()).first
        #expect(fp?.status == .archived)
        #expect(fp?.episodes.count == 1)
        #expect(fp?.characters.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<ScriptScene>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<SceneElement>()).count == 1)

        // archived -> active
        p.status = .active
        p.updatedAt = .now
        try ctx.save()
        fp = try ctx.fetch(FetchDescriptor<Project>()).first
        #expect(fp?.status == .active)
        #expect(fp?.episodes.first?.scenes.first?.elements.count == 1)
        #expect(fp?.characters.first?.name == "HERO")
    }

    @Test func trashedProjectRestoreKeepsChildren() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "Trash me"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "S", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)
        try ctx.save()

        p.status = .trashed
        p.trashedAt = .now
        try ctx.save()

        let afterTrash = try ctx.fetch(FetchDescriptor<Project>()).first
        #expect(afterTrash?.status == .trashed)
        #expect(afterTrash?.episodes.count == 1)

        p.status = .active
        p.trashedAt = nil
        try ctx.save()

        let afterRestore = try ctx.fetch(FetchDescriptor<Project>()).first
        #expect(afterRestore?.status == .active)
        #expect(afterRestore?.trashedAt == nil)
        #expect(afterRestore?.episodes.first?.scenes.count == 1)
    }

    @Test func activeStatusFilterExcludesArchivedAndTrashed() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let active = Project(title: "Active", status: .active); ctx.insert(active)
        let archived = Project(title: "Archived", status: .archived); ctx.insert(archived)
        let trashed = Project(title: "Trashed", status: .trashed); ctx.insert(trashed)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Project>())
        #expect(all.count == 3)

        // Filter in-memory (SwiftData predicates on raw-value enums are
        // awkward across OS versions — this mirrors how the list view
        // filters after fetch).
        let onlyActive = all.filter { $0.status == .active }
        #expect(onlyActive.count == 1)
        #expect(onlyActive.first?.title == "Active")
    }

    // MARK: - Deletion and cascade semantics (not covered in base suite)

    @Test func deletingEpisodeZeroesOutScenesAndElements() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<3 {
            let s = ScriptScene(locationName: "S\(i)", order: i)
            s.episode = ep; ep.scenes.append(s); ctx.insert(s)
            let el = SceneElement(kind: .action, text: "t\(i)", order: 0)
            el.scene = s; s.elements.append(el); ctx.insert(el)
        }
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<ScriptScene>()).count == 3)
        #expect(try ctx.fetch(FetchDescriptor<SceneElement>()).count == 3)

        ctx.delete(ep)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Episode>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ScriptScene>()).count == 0)
        #expect(try ctx.fetch(FetchDescriptor<SceneElement>()).count == 0)
        #expect(try ctx.fetch(FetchDescriptor<Project>()).count == 1)
    }

    @Test func deletingProjectCascadesAllChildrenButKeepsCharacters() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "Doomed"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "S", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)
        let el = SceneElement(kind: .action, text: "gone", order: 0); el.scene = sc; sc.elements.append(el); ctx.insert(el)
        let c1 = ScriptCharacter(name: "A"); c1.projects.append(p); p.characters.append(c1); ctx.insert(c1)
        let c2 = ScriptCharacter(name: "B"); c2.projects.append(p); p.characters.append(c2); ctx.insert(c2)
        try ctx.save()

        ctx.delete(p)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Episode>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ScriptScene>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<SceneElement>()).isEmpty)
        let chars = try ctx.fetch(FetchDescriptor<ScriptCharacter>())
        #expect(chars.count == 2)
        #expect(chars.allSatisfy { $0.projects.isEmpty })
    }

    @Test func deletingCharacterKeepsAllProjects() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p1 = Project(title: "P1"); ctx.insert(p1)
        let p2 = Project(title: "P2"); ctx.insert(p2)
        let c = ScriptCharacter(name: "C")
        c.projects.append(contentsOf: [p1, p2])
        p1.characters.append(c); p2.characters.append(c)
        ctx.insert(c)
        try ctx.save()

        ctx.delete(c)
        try ctx.save()

        let projs = try ctx.fetch(FetchDescriptor<Project>())
        #expect(projs.count == 2)
        #expect(Set(projs.map(\.title)) == ["P1", "P2"])
        #expect(projs.allSatisfy { $0.characters.isEmpty })
        #expect(try ctx.fetch(FetchDescriptor<ScriptCharacter>()).isEmpty)
    }
}
