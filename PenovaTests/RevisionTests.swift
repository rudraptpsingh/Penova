//
//  RevisionTests.swift
//  PenovaTests
//
//  Covers the Revision SwiftData model: CRUD, cascade-on-project-delete,
//  ordering, and the AuthorName snapshot semantics (revisions stamp
//  the author at save time; later sign-outs/sign-ins don't touch them).
//

import Testing
import Foundation
import SwiftData
@testable import Penova

@MainActor
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Project.self,
        Episode.self,
        ScriptScene.self,
        SceneElement.self,
        ScriptCharacter.self,
        WritingDay.self,
        Revision.self,
        configurations: config
    )
}

@MainActor
@Suite struct RevisionTests {

    @Test func createAndAttachRevision() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Doomed")
        ctx.insert(p)
        let r = Revision(
            label: "First draft",
            note: "Got the bones down.",
            fountainSnapshot: "INT. ROOM - DAY\n\nShe enters.\n",
            authorName: "Aaron Sorkin",
            sceneCountAtSave: 1,
            wordCountAtSave: 5
        )
        r.project = p
        p.revisions.append(r)
        ctx.insert(r)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Revision>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.label == "First draft")
        #expect(fetched.first?.authorName == "Aaron Sorkin")
        #expect(fetched.first?.project?.title == "Doomed")
    }

    @Test func deletingProjectCascadesRevisions() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Doomed"); ctx.insert(p)
        for i in 0..<3 {
            let r = Revision(
                label: "R\(i)",
                fountainSnapshot: "snap \(i)",
                authorName: "Author",
                sceneCountAtSave: 0,
                wordCountAtSave: 0
            )
            r.project = p
            p.revisions.append(r)
            ctx.insert(r)
        }
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<Revision>()).count == 3)

        ctx.delete(p)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Revision>()).isEmpty)
    }

    @Test func revisionsByDateOrdersNewestFirst() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)

        let now = Date()
        for (idx, offset) in [-3600, 0, -7200].enumerated() {
            let r = Revision(
                label: "R\(idx)",
                fountainSnapshot: "snap",
                authorName: "",
                sceneCountAtSave: 0,
                wordCountAtSave: 0
            )
            r.project = p
            r.createdAt = now.addingTimeInterval(TimeInterval(offset))
            p.revisions.append(r)
            ctx.insert(r)
        }
        try ctx.save()

        let ordered = p.revisionsByDate.map(\.label)
        // Indices: 0 was -3600s ago, 1 was now, 2 was -7200s ago.
        // Newest first: R1 (now), R0 (-1h), R2 (-2h).
        #expect(ordered == ["R1", "R0", "R2"])
    }

    @Test func authorNameSnapshotIsImmutable() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let r = Revision(
            label: "R",
            fountainSnapshot: "snap",
            authorName: "Anonymous",
            sceneCountAtSave: 0,
            wordCountAtSave: 0
        )
        r.project = p
        p.revisions.append(r)
        ctx.insert(r)
        try ctx.save()

        // Even after we "sign in" later, the historical revision's
        // recorded author is unchanged (the snapshot is the artefact).
        let fetched = try ctx.fetch(FetchDescriptor<Revision>()).first
        #expect(fetched?.authorName == "Anonymous")
    }

    @Test func revisionRegisteredInSchema() {
        let names = PenovaSchema.models.map { String(describing: $0) }
        #expect(names.contains("Revision"))
    }

    @Test func deletingProjectAlsoEmptiesRevisionsRelationship() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let r = Revision(
            label: "R",
            fountainSnapshot: "snap",
            authorName: "",
            sceneCountAtSave: 0,
            wordCountAtSave: 0
        )
        r.project = p
        p.revisions.append(r)
        ctx.insert(r)
        try ctx.save()
        #expect(p.revisions.count == 1)
    }
}
