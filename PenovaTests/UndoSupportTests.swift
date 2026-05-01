//
//  UndoSupportTests.swift
//  PenovaTests
//
//  These tests pin Penova's destructive-action safety contract:
//    • SwiftData's `ModelContext.undoManager` does NOT reliably reverse
//      a persisted delete after `save()`. We discovered this empirically
//      while wiring up ⌘Z. The test below codifies that behaviour so
//      future contributors don't accidentally re-introduce a UndoManager
//      assumption that silently fails for users.
//    • The user-facing safety net is therefore the confirm-delete alert
//      that every top-level destructive screen presents. The data-model
//      cascade tests in SwiftDataCRUDTests + CRUDEdgeCaseTests cover
//      what each delete actually removes.
//    • Recovery beyond that requires a soft-delete tombstone (deletedAt
//      + 30-day purge), tracked as a tier-1 follow-up.
//

import Testing
import Foundation
import SwiftData
@testable import Penova
@testable import PenovaKit

@MainActor
@Suite struct UndoSupportTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self,
            SceneElement.self, ScriptCharacter.self, WritingDay.self, Revision.self,
            configurations: config
        )
    }

    /// Empirical: even with `undoManager` set, `save()` followed by
    /// `undo()` does NOT bring back a deleted SwiftData object. If this
    /// test starts failing, SwiftData has gained the behaviour and we
    /// can wire UndoManager back in (see PenovaApp.swift).
    @Test func swiftDataDeleteIsNotUndoableViaUndoManager() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.undoManager = UndoManager()

        let p = Project(title: "Lost"); ctx.insert(p)
        try ctx.save()

        ctx.undoManager?.beginUndoGrouping()
        ctx.delete(p)
        try ctx.save()
        ctx.undoManager?.endUndoGrouping()

        ctx.undoManager?.undo()
        try? ctx.save()

        let projects = try ctx.fetch(FetchDescriptor<Project>())
        // CONTRACT: this currently equals 0 (undo did NOT restore).
        // The day SwiftData fixes this, this assertion will fail and
        // we'll know it's safe to wire UndoManager back into the apps.
        #expect(projects.count == 0,
                "SwiftData has gained reliable delete-undo — wire UndoManager back in PenovaApp/PenovaMacApp.swift")
    }

    /// Cascade-on-delete from CRUDEdgeCaseTests is the actual contract
    /// we rely on. Echoed here as a single sanity assert so this suite
    /// also documents the user-visible "delete a project, everything
    /// underneath goes too" expectation in one place.
    @Test func deletingProjectCascadesEpisodesScenesElements() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Doomed"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "Roof", order: 0); s.episode = ep
        ep.scenes.append(s); ctx.insert(s)
        let el = SceneElement(kind: .action, text: "Beat.", order: 0)
        el.scene = s; s.elements.append(el); ctx.insert(el)
        try ctx.save()

        ctx.delete(p)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Episode>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ScriptScene>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<SceneElement>()).isEmpty)
    }
}
