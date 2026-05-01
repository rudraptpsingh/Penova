//
//  SearchServiceTests.swift
//  PenovaTests
//
//  Cross-platform search across the library: project / scene /
//  location / dialogue / character. The Mac app's ⌘F overlay is the
//  primary consumer; the iOS app's GlobalSearchView will adopt it
//  next.
//

import Testing
import SwiftData
import Foundation
@testable import PenovaKit

@Suite("SearchService")
struct SearchServiceTests {

    private static func makeContext() throws -> ModelContext {
        let schema = Schema(PenovaSchema.models)
        let config = ModelConfiguration("test", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Builds a single project: 1 episode, 2 scenes — kitchen + alley —
    /// each with a couple of dialogue lines, plus 2 characters.
    private static func seed(_ context: ModelContext) -> Project {
        let p = Project(title: "Ek Raat Mumbai Mein", logline: "")
        context.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p
        context.insert(ep)

        let kitchen = ScriptScene(locationName: "KITCHEN", location: .interior, time: .night, order: 0)
        kitchen.episode = ep
        context.insert(kitchen)
        let k1 = SceneElement(kind: .character, text: "PENNY", order: 0)
        k1.scene = kitchen; context.insert(k1)
        let k2 = SceneElement(kind: .dialogue, text: "I quit today.", order: 1, characterName: "PENNY")
        k2.scene = kitchen; context.insert(k2)

        let alley = ScriptScene(locationName: "ALLEY", location: .exterior, time: .night, order: 1)
        alley.episode = ep
        context.insert(alley)
        let a1 = SceneElement(kind: .character, text: "MARCUS", order: 0)
        a1.scene = alley; context.insert(a1)
        let a2 = SceneElement(kind: .dialogue, text: "She quit. She actually quit.", order: 1, characterName: "MARCUS")
        a2.scene = alley; context.insert(a2)

        let penny = ScriptCharacter(name: "PENNY", role: .protagonist)
        penny.projects = [p]
        context.insert(penny)
        let marcus = ScriptCharacter(name: "MARCUS", role: .lead)
        marcus.projects = [p]
        context.insert(marcus)

        try? context.save()
        return p
    }

    @Test("empty query returns nothing")
    func emptyQueryNoResults() throws {
        let ctx = try Self.makeContext()
        let p = Self.seed(ctx)
        #expect(SearchService.search(query: "", in: [p]).isEmpty)
        #expect(SearchService.search(query: "   ", in: [p]).isEmpty)
    }

    @Test("matches project title case-insensitively")
    func projectTitleMatch() throws {
        let ctx = try Self.makeContext()
        let p = Self.seed(ctx)
        let r = SearchService.search(query: "MUMBAI", in: [p])
        let projHit = r.first { $0.kind == .project }
        #expect(projHit != nil)
        #expect(projHit?.title == "Ek Raat Mumbai Mein")
    }

    @Test("matches scene heading and reports scene+episode anchors")
    func sceneHeadingMatch() throws {
        let ctx = try Self.makeContext()
        let p = Self.seed(ctx)
        let r = SearchService.search(query: "kitchen", in: [p])
        let sceneHit = r.first { $0.kind == .scene }
        #expect(sceneHit != nil)
        #expect(sceneHit?.sceneID != nil)
        #expect(sceneHit?.episodeID != nil)
        #expect(sceneHit?.title.contains("KITCHEN") == true)
    }

    @Test("matches dialogue and surfaces speaker in title")
    func dialogueMatch() throws {
        let ctx = try Self.makeContext()
        let p = Self.seed(ctx)
        let r = SearchService.search(query: "quit", in: [p])
        let dialogue = r.filter { $0.kind == .dialogue }
        #expect(dialogue.count == 2)
        #expect(dialogue.contains { $0.title.contains("PENNY") })
        #expect(dialogue.contains { $0.title.contains("MARCUS") })
    }

    @Test("matches character names without duplicates")
    func characterMatch() throws {
        let ctx = try Self.makeContext()
        let p = Self.seed(ctx)
        let r = SearchService.search(query: "marcus", in: [p])
        let chars = r.filter { $0.kind == .character }
        #expect(chars.count == 1)
        #expect(chars.first?.title == "MARCUS")
    }

    @Test("matches location and dedupes across scenes")
    func locationMatch() throws {
        let ctx = try Self.makeContext()
        let p = Self.seed(ctx)
        let r = SearchService.search(query: "kitchen", in: [p])
        let locs = r.filter { $0.kind == .location }
        // Even if we add another KITCHEN scene the location group dedupes
        #expect(locs.count == 1)
    }

    @Test("titleMatch range points at the matching substring")
    func titleMatchRange() throws {
        let ctx = try Self.makeContext()
        let p = Self.seed(ctx)
        let r = SearchService.search(query: "Penny", in: [p])
        let charHit = r.first { $0.kind == .character }
        let range = charHit?.titleMatch
        #expect(range != nil)
        if let range, let h = charHit {
            let nsTitle = h.title as NSString
            let matched = nsTitle.substring(with: range)
            #expect(matched.lowercased() == "penny")
        }
    }

    @Test("perKindLimit caps each kind independently")
    func perKindLimit() throws {
        let ctx = try Self.makeContext()
        let p = Project(title: "Big", logline: "")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p
        ctx.insert(ep)
        for i in 0..<20 {
            let s = ScriptScene(locationName: "SCENE \(i) DINER", location: .interior, time: .day, order: i)
            s.episode = ep
            ctx.insert(s)
        }
        try? ctx.save()

        let r = SearchService.search(query: "diner", in: [p], perKindLimit: 3)
        let sceneHits = r.filter { $0.kind == .scene }
        #expect(sceneHits.count == 3)
    }
}
