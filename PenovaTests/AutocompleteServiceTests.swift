//
//  AutocompleteServiceTests.swift
//  PenovaTests
//
//  Pins the contract for project-scoped autocomplete suggestions used
//  by the New Scene sheet (locations) and the scene editor (character
//  cues). Frequency-sorted, case-normalised, and includes both
//  scene-typed and roster-registered characters.
//

import Testing
import Foundation
import SwiftData
@testable import Penova
@testable import PenovaKit

@MainActor
@Suite struct AutocompleteServiceTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self,
            SceneElement.self, ScriptCharacter.self, WritingDay.self,
            configurations: config
        )
    }

    private func makeScene(_ name: String, in ep: Episode, ctx: ModelContext) -> ScriptScene {
        let s = ScriptScene(locationName: name, location: .interior, time: .day,
                            order: ep.scenes.count)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        return s
    }

    private func addCue(_ name: String, in scene: ScriptScene, ctx: ModelContext) {
        let order = scene.elements.count
        let el = SceneElement(kind: .character, text: name, order: order)
        el.scene = scene; scene.elements.append(el); ctx.insert(el)
    }

    // MARK: - Locations

    @Test func locationsReturnsUniqueUppercased() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        _ = makeScene("Mumbai Local Train", in: ep, ctx: ctx)
        _ = makeScene("MUMBAI LOCAL TRAIN", in: ep, ctx: ctx)
        _ = makeScene("signal control room", in: ep, ctx: ctx)
        try ctx.save()

        let suggestions = AutocompleteService.locations(in: p)
        #expect(suggestions.contains("MUMBAI LOCAL TRAIN"))
        #expect(suggestions.contains("SIGNAL CONTROL ROOM"))
        // Mumbai appears twice — but only once in suggestions.
        #expect(suggestions.filter { $0 == "MUMBAI LOCAL TRAIN" }.count == 1)
    }

    @Test func locationsAreFrequencySorted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        // "BAR" appears 3x, "ROOF" 1x.
        _ = makeScene("Bar", in: ep, ctx: ctx)
        _ = makeScene("Bar", in: ep, ctx: ctx)
        _ = makeScene("Bar", in: ep, ctx: ctx)
        _ = makeScene("Roof", in: ep, ctx: ctx)
        try ctx.save()

        let suggestions = AutocompleteService.locations(in: p)
        #expect(suggestions.first == "BAR", "expected most-frequent location first; got \(suggestions)")
    }

    @Test func locationsIgnoresEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        _ = makeScene("", in: ep, ctx: ctx)
        _ = makeScene("   ", in: ep, ctx: ctx)
        _ = makeScene("Real Place", in: ep, ctx: ctx)
        try ctx.save()

        let suggestions = AutocompleteService.locations(in: p)
        #expect(suggestions == ["REAL PLACE"])
    }

    // MARK: - Character cues

    @Test func cuesIncludeBothTypedAndRegistered() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        let s = makeScene("Bar", in: ep, ctx: ctx)
        addCue("ALICE", in: s, ctx: ctx)
        addCue("ALICE", in: s, ctx: ctx)
        addCue("BOB", in: s, ctx: ctx)
        // Carla is registered but never typed in dialogue yet.
        let carla = ScriptCharacter(name: "Carla")
        carla.projects.append(p); p.characters.append(carla); ctx.insert(carla)
        try ctx.save()

        let suggestions = AutocompleteService.characterCues(in: p)
        #expect(suggestions.contains("ALICE"))
        #expect(suggestions.contains("BOB"))
        #expect(suggestions.contains("CARLA"),
                "registered ScriptCharacter not surfaced — got \(suggestions)")
        // ALICE appears twice in scene → outranks once-only BOB.
        #expect(suggestions.firstIndex(of: "ALICE")! < suggestions.firstIndex(of: "BOB")!)
    }

    @Test func cuesStripParentheticalSuffixes() throws {
        // "ALICE (CONT'D)" should fold into "ALICE", not be a separate cue.
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        let s = makeScene("Bar", in: ep, ctx: ctx)
        addCue("ALICE", in: s, ctx: ctx)
        addCue("ALICE (CONT'D)", in: s, ctx: ctx)
        addCue("ALICE (V.O.)", in: s, ctx: ctx)
        try ctx.save()

        let suggestions = AutocompleteService.characterCues(in: p)
        #expect(suggestions == ["ALICE"],
                "expected only ALICE; got \(suggestions)")
    }

    @Test func cuesAreFrequencySorted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        let s = makeScene("Bar", in: ep, ctx: ctx)
        for _ in 0..<5 { addCue("LEAD", in: s, ctx: ctx) }
        for _ in 0..<2 { addCue("OTHER", in: s, ctx: ctx) }
        addCue("EXTRA", in: s, ctx: ctx)
        try ctx.save()

        let suggestions = AutocompleteService.characterCues(in: p)
        #expect(suggestions.first == "LEAD")
        #expect(suggestions[1] == "OTHER")
        #expect(suggestions.last == "EXTRA")
    }

    @Test func cuesIgnoresWhitespaceOnly() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        let s = makeScene("Bar", in: ep, ctx: ctx)
        addCue("   ", in: s, ctx: ctx)
        addCue("REAL", in: s, ctx: ctx)
        try ctx.save()

        let suggestions = AutocompleteService.characterCues(in: p)
        #expect(suggestions == ["REAL"])
    }

    // MARK: - Filter via EditorLogic.suggestions

    @Test func suggestionsFilterIsSubstringCaseInsensitive() {
        let pool = ["MUMBAI LOCAL TRAIN", "MARINE DRIVE", "WORLI SEA-LINK"]
        #expect(EditorLogic.suggestions(query: "marine", in: pool) == ["MARINE DRIVE"])
        #expect(EditorLogic.suggestions(query: "WOR", in: pool) == ["WORLI SEA-LINK"])
        // Empty query returns the full list, untouched.
        #expect(EditorLogic.suggestions(query: "", in: pool) == pool)
        // Whitespace-only query also returns full list.
        #expect(EditorLogic.suggestions(query: "   ", in: pool) == pool)
    }
}
