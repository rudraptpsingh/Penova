//
//  SearchAndCharacterReportTests.swift
//  PenovaTests
//
//  Two related checks:
//   1. Basic search substring matching over SceneElement.text returns the
//      expected elements (this is the underlying store query used by
//      GlobalSearchView — we don't render the view here, just the filter).
//   2. The character-report computation (lines, scenes, first/last) inside
//      CharacterDetailScreen — duplicated here as a plain helper so we can
//      assert without touching SwiftUI.
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
@Suite struct SearchAndCharacterReportTests {

    @Test func searchFindsElementByText() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let scene = ScriptScene(locationName: "DINER", order: 0); scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)

        let hit = SceneElement(kind: .action, text: "She orders black coffee.", order: 0)
        hit.scene = scene; scene.elements.append(hit); ctx.insert(hit)
        let miss = SceneElement(kind: .action, text: "Nothing related here.", order: 1)
        miss.scene = scene; scene.elements.append(miss); ctx.insert(miss)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<SceneElement>())
        let query = "coffee"
        let hits = all.filter { $0.text.localizedCaseInsensitiveContains(query) }
        #expect(hits.count == 1)
        #expect(hits.first?.text == "She orders black coffee.")
    }

    @Test func searchIsCaseInsensitive() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; ctx.insert(ep)
        let sc = ScriptScene(locationName: "X", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)
        let el = SceneElement(kind: .dialogue, text: "GOODBYE, MARLOW.", order: 0)
        el.scene = sc; sc.elements.append(el); ctx.insert(el)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<SceneElement>())
        let hits = all.filter { $0.text.localizedCaseInsensitiveContains("marlow") }
        #expect(hits.count == 1)
    }

    @Test func characterReportCountsLinesAndScenes() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)

        // Scene A: HERO says two things.
        let sA = ScriptScene(locationName: "A", order: 0); sA.episode = ep; ep.scenes.append(sA); ctx.insert(sA)
        let c1 = SceneElement(kind: .character, text: "HERO", order: 0); c1.scene = sA; sA.elements.append(c1); ctx.insert(c1)
        let d1 = SceneElement(kind: .dialogue, text: "Hello.", order: 1); d1.scene = sA; sA.elements.append(d1); ctx.insert(d1)
        let c2 = SceneElement(kind: .character, text: "HERO", order: 2); c2.scene = sA; sA.elements.append(c2); ctx.insert(c2)
        let d2 = SceneElement(kind: .dialogue, text: "Still me.", order: 3); d2.scene = sA; sA.elements.append(d2); ctx.insert(d2)

        // Scene B: VILLAIN speaks; HERO doesn't.
        let sB = ScriptScene(locationName: "B", order: 1); sB.episode = ep; ep.scenes.append(sB); ctx.insert(sB)
        let vC = SceneElement(kind: .character, text: "VILLAIN", order: 0); vC.scene = sB; sB.elements.append(vC); ctx.insert(vC)
        let vD = SceneElement(kind: .dialogue, text: "Curses.", order: 1); vD.scene = sB; sB.elements.append(vD); ctx.insert(vD)

        // Scene C: HERO speaks one line.
        let sC = ScriptScene(locationName: "C", order: 2); sC.episode = ep; ep.scenes.append(sC); ctx.insert(sC)
        let c3 = SceneElement(kind: .character, text: "HERO", order: 0); c3.scene = sC; sC.elements.append(c3); ctx.insert(c3)
        let d3 = SceneElement(kind: .dialogue, text: "The end.", order: 1); d3.scene = sC; sC.elements.append(d3); ctx.insert(d3)

        let hero = ScriptCharacter(name: "HERO", role: .protagonist)
        hero.projects.append(p); p.characters.append(hero); ctx.insert(hero)
        try ctx.save()

        // Replicate the CharacterDetailScreen report computation here — the
        // view layer can't be unit-tested directly, but the logic is simple
        // enough to re-express and pin.
        let upperName = hero.name.uppercased()
        var lineCount = 0
        var sceneIDs = Set<ID>()
        for proj in hero.projects {
            for episode in proj.episodes {
                for scene in episode.scenes {
                    var speaking = false
                    var currentSpeaker: String?
                    for el in scene.elementsOrdered {
                        switch el.kind {
                        case .character:
                            currentSpeaker = el.text.uppercased()
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if currentSpeaker == upperName { speaking = true }
                        case .dialogue:
                            if currentSpeaker == upperName { lineCount += 1 }
                        default: break
                        }
                    }
                    if speaking { sceneIDs.insert(scene.id) }
                }
            }
        }
        #expect(lineCount == 3)
        #expect(sceneIDs.count == 2) // A and C, not B
    }
}
