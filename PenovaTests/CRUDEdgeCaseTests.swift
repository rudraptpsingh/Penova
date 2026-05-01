//
//  CRUDEdgeCaseTests.swift
//  PenovaTests
//
//  Edge-case coverage for the SwiftData CRUD flows beyond the happy-path
//  cases in SwiftDataCRUDTests. Each test uses a fresh in-memory
//  ModelContainer so state is hermetic.
//

import Testing
import Foundation
import SwiftData
import PenovaKit
@testable import Penova

@MainActor
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
        configurations: config
    )
}

/// Replicates the NewProjectSheet.canSave predicate so we can test the UI
/// validation rule without instantiating the SwiftUI view.
private func canSaveProjectTitle(_ title: String) -> Bool {
    !title.trimmingCharacters(in: .whitespaces).isEmpty
}

@MainActor
@Suite struct CRUDEdgeCaseTests {

    // MARK: - Empty / invalid title handling

    /// The Project model itself has no validation — an empty title inserts
    /// fine. The UI sheet is responsible for blocking that via `canSave`.
    @Test func emptyTitleProjectInsertsButUIRejectsIt() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "")
        ctx.insert(p)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Project>()).count == 1)

        // The NewProjectSheet.canSave predicate (replicated above) should
        // reject all-whitespace titles.
        #expect(canSaveProjectTitle("") == false)
        #expect(canSaveProjectTitle("   ") == false)
        #expect(canSaveProjectTitle("\t  ") == false)
        #expect(canSaveProjectTitle("Hello") == true)
        #expect(canSaveProjectTitle("  Hello  ") == true)
        // NOTE: NewProjectSheet.canSave uses `.whitespaces` which does NOT
        // include newline characters. A title of just "\n" would currently
        // be accepted. Documented here rather than "fixed" — the production
        // code is what it is.
        #expect(canSaveProjectTitle("\n") == true)
    }

    // MARK: - Relationship traversal

    @Test func sceneResolvesBackToProjectThroughEpisode() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "Traverse")
        ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let scene = ScriptScene(locationName: "ROOM", order: 0)
        scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ScriptScene>()).first
        #expect(fetched?.episode?.project?.title == "Traverse")
    }

    // MARK: - Delete edge cases

    @Test func deletingProjectWithZeroEpisodesSucceeds() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "Lonely")
        ctx.insert(p)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<Project>()).count == 1)

        ctx.delete(p)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<Project>()).isEmpty)
    }

    @Test func deletingLastSceneLeavesEpisodeIntact() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let only = ScriptScene(locationName: "ONLY", order: 0)
        only.episode = ep; ep.scenes.append(only); ctx.insert(only)
        try ctx.save()

        ctx.delete(only)
        try ctx.save()

        let eps = try ctx.fetch(FetchDescriptor<Episode>())
        #expect(eps.count == 1)
        #expect(eps.first?.title == "E")
        #expect(eps.first?.scenes.isEmpty == true)
        #expect(try ctx.fetch(FetchDescriptor<ScriptScene>()).isEmpty)
    }

    /// `ScriptScene.heading` is a stored field that is (re)built from
    /// locationName + location + time. Deleting a heading-kind
    /// SceneElement must not clobber it — they're unrelated.
    @Test func deletingHeadingElementDoesNotBreakSceneHeading() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let scene = ScriptScene(locationName: "Alley", location: .exterior, time: .night, order: 0)
        scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)

        let headingEl = SceneElement(kind: .heading, text: scene.heading, order: 0)
        headingEl.scene = scene; scene.elements.append(headingEl); ctx.insert(headingEl)
        let actionEl = SceneElement(kind: .action, text: "Rain falls.", order: 1)
        actionEl.scene = scene; scene.elements.append(actionEl); ctx.insert(actionEl)
        try ctx.save()

        let expectedHeading = "EXT. ALLEY - NIGHT"
        #expect(scene.heading == expectedHeading)

        ctx.delete(headingEl)
        try ctx.save()

        let sc = try ctx.fetch(FetchDescriptor<ScriptScene>()).first
        #expect(sc?.heading == expectedHeading)
        #expect(sc?.elements.count == 1)
        #expect(sc?.elements.first?.kind == .action)
    }

    // MARK: - Many-to-many character semantics

    @Test func characterAttachedToManyProjectsLosesOneAtATime() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p1 = Project(title: "P1"); ctx.insert(p1)
        let p2 = Project(title: "P2"); ctx.insert(p2)
        let p3 = Project(title: "P3"); ctx.insert(p3)
        let hero = ScriptCharacter(name: "HERO", role: .protagonist)
        hero.projects.append(contentsOf: [p1, p2, p3])
        ctx.insert(hero)
        try ctx.save()
        #expect(hero.projects.count == 3)

        // Delete p1 — hero still attached to p2, p3
        ctx.delete(p1)
        try ctx.save()
        let afterOne = try ctx.fetch(FetchDescriptor<ScriptCharacter>()).first
        #expect(afterOne?.projects.count == 2)
        #expect(Set(afterOne?.projects.map(\.title) ?? []) == ["P2", "P3"])

        // Delete p2 — hero still attached to p3
        ctx.delete(p2)
        try ctx.save()
        let afterTwo = try ctx.fetch(FetchDescriptor<ScriptCharacter>()).first
        #expect(afterTwo?.projects.count == 1)
        #expect(afterTwo?.projects.first?.title == "P3")

        // Delete p3 — hero orphaned but still present.
        ctx.delete(p3)
        try ctx.save()
        let orphaned = try ctx.fetch(FetchDescriptor<ScriptCharacter>())
        #expect(orphaned.count == 1)
        #expect(orphaned.first?.name == "HERO")
        #expect(orphaned.first?.projects.isEmpty == true)
        #expect(try ctx.fetch(FetchDescriptor<Project>()).isEmpty)
    }

    @Test func twoCharactersInSameProjectCanShareName() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "Dup"); ctx.insert(p)
        let a = ScriptCharacter(name: "JANE", role: .lead)
        a.projects.append(p); p.characters.append(a); ctx.insert(a)
        let b = ScriptCharacter(name: "JANE", role: .supporting)
        b.projects.append(p); p.characters.append(b); ctx.insert(b)
        try ctx.save()

        let chars = try ctx.fetch(FetchDescriptor<ScriptCharacter>())
        #expect(chars.count == 2)
        #expect(chars.allSatisfy { $0.name == "JANE" })
        // Both share the same project membership
        let proj = try ctx.fetch(FetchDescriptor<Project>()).first
        #expect(proj?.characters.count == 2)
        // But they have distinct IDs.
        #expect(chars[0].id != chars[1].id)
    }

    // MARK: - Editing propagation

    @Test func editingProjectTitlePreservesChildRelationships() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "Original"); ctx.insert(p)
        let ep = Episode(title: "E1", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "ROOM", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)
        try ctx.save()

        p.title = "Renamed"
        p.updatedAt = .now
        try ctx.save()

        let fetchedScene = try ctx.fetch(FetchDescriptor<ScriptScene>()).first
        #expect(fetchedScene?.episode?.title == "E1")
        #expect(fetchedScene?.episode?.project?.title == "Renamed")

        let fetchedEp = try ctx.fetch(FetchDescriptor<Episode>()).first
        #expect(fetchedEp?.project?.title == "Renamed")
        #expect(fetchedEp?.scenes.count == 1)
    }

    // MARK: - Scene integrity

    @Test func sceneWithNoElementsHasEmptyOrderedList() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "VOID", order: 0)
        sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ScriptScene>()).first
        #expect(fetched?.elements.isEmpty == true)
        #expect(fetched?.elementsOrdered.isEmpty == true)
        #expect(fetched?.order == 0)
    }

    @Test func longSceneElementTextRoundTrips() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "LONG", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)

        let longText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 500)
        // >=10k characters.
        #expect(longText.count >= 10_000)

        let el = SceneElement(kind: .action, text: longText, order: 0)
        el.scene = sc; sc.elements.append(el); ctx.insert(el)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<SceneElement>()).first
        #expect(fetched?.text.count == longText.count)
        #expect(fetched?.text == longText)
    }

    @Test func unicodeSceneElementTextRoundTrips() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "UNICODE", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)

        let sample = "Hello 👋 — שלום — 你好 — \u{201C}curly\u{201D} \u{2014} 🎬🎥"
        let el = SceneElement(kind: .dialogue, text: sample, order: 0, characterName: "HERO")
        el.scene = sc; sc.elements.append(el); ctx.insert(el)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<SceneElement>()).first
        #expect(fetched?.text == sample)
        #expect(fetched?.characterName == "HERO")
    }

    @Test func bookmarkFlagPersists() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "P"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let sc = ScriptScene(locationName: "MARK", order: 0); sc.episode = ep; ep.scenes.append(sc); ctx.insert(sc)
        try ctx.save()
        #expect(sc.bookmarked == false)

        sc.bookmarked = true
        sc.updatedAt = .now
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ScriptScene>()).first
        #expect(fetched?.bookmarked == true)
    }
}
