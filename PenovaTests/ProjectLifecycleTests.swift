//
//  ProjectLifecycleTests.swift
//  PenovaTests
//
//  Pins the open → edit → save → close → reopen → assert-state-intact
//  contract. SwiftData has an "autosaves on context.save()" model and
//  Penova relies on it heavily; these tests would catch any regression
//  where a user mutation gets dropped between launches.
//
//  We don't model "close the app" literally — instead we tear down
//  the ModelContainer, persist to a known on-disk path, and rebuild
//  a fresh ModelContainer pointing at the same store. That round-trip
//  is what survives a real app restart.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
private func makeOnDiskContainer() throws -> (ModelContainer, URL) {
    let schema = Schema(PenovaSchema.models)
    let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("PenovaTests-Lifecycle-\(UUID()).store")
    let config = ModelConfiguration("Penova", schema: schema, url: storeURL)
    let container = try ModelContainer(
        for: schema,
        migrationPlan: PenovaMigrationPlan.self,
        configurations: [config]
    )
    return (container, storeURL)
}

@MainActor
private func reopenContainer(at storeURL: URL) throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration("Penova", schema: schema, url: storeURL)
    return try ModelContainer(
        for: schema,
        migrationPlan: PenovaMigrationPlan.self,
        configurations: [config]
    )
}

@MainActor
@Suite struct ProjectLifecycleTests {

    /// **Project survives a context restart**
    /// Create a project, save, drop the container, rebuild against
    /// the same on-disk store, verify the project is still there
    /// with the right title.
    @Test func projectSurvivesContainerRestart() throws {
        let (container, storeURL) = try makeOnDiskContainer()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let original = Project(title: "Survives Restart",
                               logline: "A round-trip test.")
        container.mainContext.insert(original)
        try container.mainContext.save()
        let originalID = original.id

        // Drop the first container — simulates app quit.
        // (In real life, ModelContainer.deinit would flush; we save
        // explicitly above just to be sure.)
        _ = container

        let reopened = try reopenContainer(at: storeURL)
        let projects = try reopened.mainContext.fetch(FetchDescriptor<Project>())
        #expect(projects.count == 1)
        #expect(projects.first?.id == originalID)
        #expect(projects.first?.title == "Survives Restart")
        #expect(projects.first?.logline == "A round-trip test.")
    }

    /// **Scene element edits survive a container restart**
    /// Critical autosave guarantee: every keystroke commits via
    /// `context.save()`. Verify a saved element's text is preserved
    /// through a restart.
    @Test func sceneElementEditsSurviveContainerRestart() throws {
        let (container, storeURL) = try makeOnDiskContainer()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let project = Project(title: "Edit Survival")
        container.mainContext.insert(project)
        let episode = Episode(title: "Pilot", order: 0)
        episode.project = project
        project.episodes.append(episode)
        container.mainContext.insert(episode)
        let scene = ScriptScene(locationName: "KITCHEN", order: 0)
        scene.episode = episode
        episode.scenes.append(scene)
        container.mainContext.insert(scene)

        let action = SceneElement(kind: .action,
                                  text: "She turns off the water.",
                                  order: 0)
        action.scene = scene
        scene.elements.append(action)
        container.mainContext.insert(action)
        try container.mainContext.save()

        let reopened = try reopenContainer(at: storeURL)
        let scenes = try reopened.mainContext.fetch(FetchDescriptor<ScriptScene>())
        #expect(scenes.count == 1)
        let elements = scenes.first?.elements ?? []
        #expect(elements.count == 1)
        #expect(elements.first?.text == "She turns off the water.")
        #expect(elements.first?.kind == .action)
    }

    /// **TitlePage values round-trip through restart**
    /// The TitlePage struct is stored as a Codable property on
    /// Project. SwiftData should encode/decode it transparently.
    @Test func titlePageSurvivesContainerRestart() throws {
        let (container, storeURL) = try makeOnDiskContainer()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let project = Project(title: "TP Survival")
        project.titlePage = TitlePage(
            title: "Production Draft",
            credit: "Story by",
            author: "Rudra Pratap Singh",
            source: "Based on a true event.",
            draftDate: "1 May 2026",
            draftStage: "Production Draft",
            contact: "rudra@example.com\n+91 99563 40651",
            copyright: "© 2026 Rudra",
            notes: "Studio circulation copy."
        )
        container.mainContext.insert(project)
        try container.mainContext.save()

        let reopened = try reopenContainer(at: storeURL)
        let projects = try reopened.mainContext.fetch(FetchDescriptor<Project>())
        let tp = projects.first?.titlePage
        #expect(tp?.title == "Production Draft")
        #expect(tp?.credit == "Story by")
        #expect(tp?.author == "Rudra Pratap Singh")
        #expect(tp?.source == "Based on a true event.")
        #expect(tp?.contact.contains("99563 40651") == true)
        #expect(tp?.copyright == "© 2026 Rudra")
    }

    /// **Locked-state round-trips through restart**
    /// `Project.locked`, `lockedAt`, `lockedSceneNumbers` all need
    /// to survive a restart — they pin scene numbers across drafts
    /// and re-deriving them would re-shuffle the script.
    @Test func lockedStateSurvivesContainerRestart() throws {
        let (container, storeURL) = try makeOnDiskContainer()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let project = Project(title: "Lock Survival")
        container.mainContext.insert(project)
        let episode = Episode(title: "Pilot", order: 0)
        episode.project = project
        project.episodes.append(episode)
        container.mainContext.insert(episode)
        for i in 0..<3 {
            let scene = ScriptScene(locationName: "LOC \(i)", order: i)
            scene.episode = episode
            episode.scenes.append(scene)
            container.mainContext.insert(scene)
        }

        project.lock()
        try container.mainContext.save()
        let originalLockedAt = project.lockedAt
        let originalSceneNumbers = project.lockedSceneNumbers

        let reopened = try reopenContainer(at: storeURL)
        let projects = try reopened.mainContext.fetch(FetchDescriptor<Project>())
        let p = projects.first
        #expect(p?.locked == true)
        #expect(p?.lockedSceneNumbers == originalSceneNumbers)
        if let pLock = p?.lockedAt, let oLock = originalLockedAt {
            #expect(abs(pLock.timeIntervalSince(oLock)) < 0.001)
        }
    }

    /// **Cascade delete: removing a Project removes its episodes/scenes/elements**
    /// SwiftData cascade rules pin the relationship semantics. If
    /// someone changes the deleteRule on Project.episodes, this fires.
    @Test func projectCascadeDeleteRemovesGraph() throws {
        let (container, storeURL) = try makeOnDiskContainer()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let project = Project(title: "Cascade")
        container.mainContext.insert(project)
        let episode = Episode(title: "Pilot", order: 0)
        episode.project = project
        project.episodes.append(episode)
        container.mainContext.insert(episode)
        let scene = ScriptScene(locationName: "ROOM", order: 0)
        scene.episode = episode
        episode.scenes.append(scene)
        container.mainContext.insert(scene)
        let el = SceneElement(kind: .action, text: "Action.", order: 0)
        el.scene = scene
        scene.elements.append(el)
        container.mainContext.insert(el)
        try container.mainContext.save()

        // Pre-delete: 1/1/1/1
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Project>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Episode>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ScriptScene>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SceneElement>()) == 1)

        container.mainContext.delete(project)
        try container.mainContext.save()

        // Post-delete: 0 of each.
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Episode>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ScriptScene>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SceneElement>()) == 0)
    }

    /// **Many-to-many ScriptCharacter NOT cascade-deleted with Project**
    /// Characters are weak refs across projects (see Models.swift
    /// docs on the `@Relationship(inverse: \ScriptCharacter.projects)`
    /// declaration). Deleting a Project should detach but NOT delete
    /// shared characters.
    @Test func charactersAreNotCascadeDeletedWithProject() throws {
        let (container, storeURL) = try makeOnDiskContainer()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let p1 = Project(title: "P1")
        let p2 = Project(title: "P2")
        container.mainContext.insert(p1)
        container.mainContext.insert(p2)

        let shared = ScriptCharacter(name: "JANE")
        shared.projects = [p1, p2]
        container.mainContext.insert(shared)
        try container.mainContext.save()

        // Delete only P1.
        container.mainContext.delete(p1)
        try container.mainContext.save()

        let chars = try container.mainContext.fetch(FetchDescriptor<ScriptCharacter>())
        #expect(chars.count == 1, "Shared character must not be cascade-deleted with one of its projects")
        #expect(chars.first?.name == "JANE")
    }

    /// **No data loss when reordering scenes after lock**
    /// The locked-numbers map captures which Scene.id maps to which
    /// number at lock time. After lock, reordering should NOT
    /// renumber — the locked map is the source of truth for render
    /// numbers.
    @Test func lockedNumbersDoNotChangeOnReorderAfterLock() throws {
        let (container, _) = try makeOnDiskContainer()

        let project = Project(title: "Lock + Reorder")
        container.mainContext.insert(project)
        let episode = Episode(title: "Pilot", order: 0)
        episode.project = project
        project.episodes.append(episode)
        container.mainContext.insert(episode)
        var sceneRefs: [ScriptScene] = []
        for i in 0..<3 {
            let scene = ScriptScene(locationName: "L\(i)", order: i)
            scene.episode = episode
            episode.scenes.append(scene)
            container.mainContext.insert(scene)
            sceneRefs.append(scene)
        }

        project.lock()
        let mapBefore = project.lockedSceneNumbers
        // Reorder: swap scene 0 and 2.
        sceneRefs[0].order = 2
        sceneRefs[2].order = 0
        try container.mainContext.save()

        // Each scene's render-time number should still match the
        // pre-reorder lock map.
        for scene in episode.scenes {
            let renderNumber = project.renderSceneNumber(for: scene, live: scene.order + 1)
            #expect(renderNumber == mapBefore?[scene.id],
                    "Locked numbers must persist through scene reordering")
        }
    }
}
