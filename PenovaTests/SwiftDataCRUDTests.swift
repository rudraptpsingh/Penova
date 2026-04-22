//
//  SwiftDataCRUDTests.swift
//  PenovaTests
//
//  Exercises Project → Episode → ScriptScene → SceneElement CRUD + cascade
//  deletion, plus the Project ↔ ScriptCharacter relationship.
//
//  Each test creates a fresh in-memory ModelContainer so state is hermetic.
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
@Suite struct SwiftDataCRUDTests {

    // MARK: - Create

    @Test func createProjectEpisodeSceneElement() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "Pilot", logline: "A writer writes.", genre: [.drama])
        ctx.insert(project)

        let ep = Episode(title: "Ep 1", order: 0)
        ep.project = project
        project.episodes.append(ep)
        ctx.insert(ep)

        let scene = ScriptScene(locationName: "Writer's Room", location: .interior, time: .day, order: 0)
        scene.episode = ep
        ep.scenes.append(scene)
        ctx.insert(scene)

        let heading = SceneElement(kind: .heading, text: scene.heading, order: 0)
        heading.scene = scene
        let action = SceneElement(kind: .action, text: "A writer types.", order: 1)
        action.scene = scene
        scene.elements.append(contentsOf: [heading, action])
        ctx.insert(heading); ctx.insert(action)

        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Project>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.episodes.count == 1)
        #expect(fetched.first?.episodes.first?.scenes.count == 1)
        #expect(fetched.first?.episodes.first?.scenes.first?.elements.count == 2)
    }

    // MARK: - Edit

    @Test func editUpdatesFieldsAndBumpsUpdatedAt() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "Old Title")
        ctx.insert(project)
        let ep = Episode(title: "Ep Old", order: 0)
        ep.project = project
        project.episodes.append(ep)
        ctx.insert(ep)
        let scene = ScriptScene(locationName: "Kitchen", order: 0)
        scene.episode = ep
        ep.scenes.append(scene)
        ctx.insert(scene)
        try ctx.save()

        let originalProjUpdated = project.updatedAt
        let originalEpUpdated = ep.updatedAt
        let originalSceneUpdated = scene.updatedAt

        // Need a real clock gap to detect the bump.
        Thread.sleep(forTimeInterval: 0.01)

        project.title = "New Title"
        project.logline = "A new hook."
        project.updatedAt = .now

        ep.title = "Ep New"
        ep.updatedAt = .now

        scene.locationName = "LIVING ROOM"
        scene.time = .night
        scene.rebuildHeading()
        scene.sceneDescription = "Quiet but charged."
        scene.updatedAt = .now

        try ctx.save()

        let proj = try ctx.fetch(FetchDescriptor<Project>()).first
        #expect(proj?.title == "New Title")
        #expect(proj?.logline == "A new hook.")
        #expect((proj?.updatedAt ?? .distantPast) > originalProjUpdated)

        let ep2 = try ctx.fetch(FetchDescriptor<Episode>()).first
        #expect(ep2?.title == "Ep New")
        #expect((ep2?.updatedAt ?? .distantPast) > originalEpUpdated)

        let sc = try ctx.fetch(FetchDescriptor<ScriptScene>()).first
        #expect(sc?.locationName == "LIVING ROOM")
        #expect(sc?.time == .night)
        #expect(sc?.heading == "INT. LIVING ROOM - NIGHT")
        #expect(sc?.sceneDescription == "Quiet but charged.")
        #expect((sc?.updatedAt ?? .distantPast) > originalSceneUpdated)
    }

    // MARK: - Cascade Deletes

    @Test func deletingProjectCascadesEpisodesScenesElementsButDetachesCharacters() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "Doomed")
        ctx.insert(project)
        let ep = Episode(title: "E", order: 0); ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let scene = ScriptScene(locationName: "X", order: 0); scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)
        let el = SceneElement(kind: .action, text: "bang", order: 0); el.scene = scene; scene.elements.append(el); ctx.insert(el)
        let ch = ScriptCharacter(name: "HERO", role: .protagonist); ch.projects.append(project); project.characters.append(ch); ctx.insert(ch)
        try ctx.save()

        ctx.delete(project)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Episode>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ScriptScene>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<SceneElement>()).isEmpty)
        // Character survives — many-to-many means deleting a project just
        // detaches the character, it does not delete the character itself.
        let survivors = try ctx.fetch(FetchDescriptor<ScriptCharacter>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.name == "HERO")
        #expect(survivors.first?.projects.isEmpty == true)
    }

    @Test func deletingEpisodeCascadesScenesAndElements() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "P"); ctx.insert(project)
        let keep = Episode(title: "Keep", order: 0); keep.project = project; project.episodes.append(keep); ctx.insert(keep)
        let doomed = Episode(title: "Doomed", order: 1); doomed.project = project; project.episodes.append(doomed); ctx.insert(doomed)
        let keepScene = ScriptScene(locationName: "SAFE", order: 0); keepScene.episode = keep; keep.scenes.append(keepScene); ctx.insert(keepScene)
        let doomedScene = ScriptScene(locationName: "DOOMED", order: 0); doomedScene.episode = doomed; doomed.scenes.append(doomedScene); ctx.insert(doomedScene)
        let el = SceneElement(kind: .action, text: "boom", order: 0); el.scene = doomedScene; doomedScene.elements.append(el); ctx.insert(el)
        try ctx.save()

        ctx.delete(doomed)
        try ctx.save()

        let eps = try ctx.fetch(FetchDescriptor<Episode>())
        #expect(eps.count == 1)
        #expect(eps.first?.title == "Keep")
        let scenes = try ctx.fetch(FetchDescriptor<ScriptScene>())
        #expect(scenes.count == 1)
        #expect(scenes.first?.locationName == "SAFE")
        #expect(try ctx.fetch(FetchDescriptor<SceneElement>()).isEmpty)
    }

    @Test func deletingSceneCascadesElements() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "P"); ctx.insert(project)
        let ep = Episode(title: "E", order: 0); ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let keep = ScriptScene(locationName: "KEEP", order: 0); keep.episode = ep; ep.scenes.append(keep); ctx.insert(keep)
        let doomed = ScriptScene(locationName: "DOOMED", order: 1); doomed.episode = ep; ep.scenes.append(doomed); ctx.insert(doomed)
        let keepEl = SceneElement(kind: .action, text: "safe", order: 0); keepEl.scene = keep; keep.elements.append(keepEl); ctx.insert(keepEl)
        let doomedEl = SceneElement(kind: .action, text: "gone", order: 0); doomedEl.scene = doomed; doomed.elements.append(doomedEl); ctx.insert(doomedEl)
        try ctx.save()

        ctx.delete(doomed)
        try ctx.save()

        let scenes = try ctx.fetch(FetchDescriptor<ScriptScene>())
        #expect(scenes.count == 1)
        let els = try ctx.fetch(FetchDescriptor<SceneElement>())
        #expect(els.count == 1)
        #expect(els.first?.text == "safe")
    }

    @Test func deletingElementDoesNotTouchSceneOrSiblings() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "P"); ctx.insert(project)
        let ep = Episode(title: "E", order: 0); ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let scene = ScriptScene(locationName: "ROOM", order: 0); scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)
        let e1 = SceneElement(kind: .action, text: "A", order: 0); e1.scene = scene; scene.elements.append(e1); ctx.insert(e1)
        let e2 = SceneElement(kind: .action, text: "B", order: 1); e2.scene = scene; scene.elements.append(e2); ctx.insert(e2)
        let e3 = SceneElement(kind: .action, text: "C", order: 2); e3.scene = scene; scene.elements.append(e3); ctx.insert(e3)
        try ctx.save()

        ctx.delete(e2)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<ScriptScene>()).count == 1)
        let els = try ctx.fetch(FetchDescriptor<SceneElement>())
        #expect(els.count == 2)
        let texts = Set(els.map(\.text))
        #expect(texts == ["A", "C"])
    }

    // MARK: - Characters

    /// A character can be attached to multiple projects simultaneously.
    /// We verify both directions: project.characters and character.projects.
    @Test func attachCharacterToMultipleProjects() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p1 = Project(title: "P1"); ctx.insert(p1)
        let p2 = Project(title: "P2"); ctx.insert(p2)
        let hero = ScriptCharacter(name: "HERO", role: .protagonist)
        hero.projects.append(p1)
        hero.projects.append(p2)
        ctx.insert(hero)
        try ctx.save()

        // From the character side.
        let fetchedChar = try ctx.fetch(FetchDescriptor<ScriptCharacter>()).first
        #expect(fetchedChar?.name == "HERO")
        #expect(fetchedChar?.projects.count == 2)
        #expect(Set(fetchedChar?.projects.map(\.title) ?? []) == ["P1", "P2"])

        // From each project side.
        let projects = try ctx.fetch(FetchDescriptor<Project>())
        #expect(projects.count == 2)
        for p in projects {
            #expect(p.characters.count == 1)
            #expect(p.characters.first?.name == "HERO")
        }
    }

    /// Deleting a character does NOT delete any of the projects it was
    /// attached to.
    @Test func deletingCharacterDoesNotDeleteOwningProject() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let p1 = Project(title: "P1"); ctx.insert(p1)
        let p2 = Project(title: "P2"); ctx.insert(p2)
        let shared = ScriptCharacter(name: "SHARED")
        shared.projects.append(p1)
        p1.characters.append(shared)
        ctx.insert(shared)
        try ctx.save()

        ctx.delete(shared)
        try ctx.save()

        let projects = try ctx.fetch(FetchDescriptor<Project>())
        #expect(projects.count == 2)
        let titles = Set(projects.map(\.title))
        #expect(titles == ["P1", "P2"])
        #expect(try ctx.fetch(FetchDescriptor<ScriptCharacter>()).isEmpty)
    }

    /// Deleting a project that a shared character is attached to should
    /// leave the character alive (still attached to the other project).
    @Test func deletingOneProjectLeavesCharacterAttachedToOthers() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let a = Project(title: "A"); ctx.insert(a)
        let b = Project(title: "B"); ctx.insert(b)
        let shared = ScriptCharacter(name: "SHARED")
        shared.projects.append(a)
        shared.projects.append(b)
        ctx.insert(shared)
        try ctx.save()

        // Sanity: both projects see the character.
        #expect(a.characters.count == 1)
        #expect(b.characters.count == 1)

        ctx.delete(a)
        try ctx.save()

        let projects = try ctx.fetch(FetchDescriptor<Project>())
        #expect(projects.count == 1)
        #expect(projects.first?.title == "B")

        let chars = try ctx.fetch(FetchDescriptor<ScriptCharacter>())
        #expect(chars.count == 1)
        #expect(chars.first?.name == "SHARED")
        #expect(chars.first?.projects.count == 1)
        #expect(chars.first?.projects.first?.title == "B")
        // And project B still lists the character on its side.
        #expect(projects.first?.characters.count == 1)
        #expect(projects.first?.characters.first?.name == "SHARED")
    }
}
