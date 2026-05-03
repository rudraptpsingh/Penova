//
//  SaveRevisionServiceTests.swift
//  PenovaTests
//
//  Pins the SaveRevisionService contract:
//   • First save → White, round 1
//   • Subsequent saves auto-advance via Project.nextRevisionColor()
//   • Explicit colour / round / label overrides win
//   • Snapshot is the Fountain export of the project
//   • authorName is required and stamped
//   • blank authorName throws
//   • element stamping sets lastRevisedRevisionID to the active revision
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
@Suite struct SaveRevisionServiceTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(PenovaSchema.models)
        let config = ModelConfiguration(
            "SaveRevisionServiceTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeProject(in ctx: ModelContext) -> Project {
        let p = Project(title: "Ek Raat Mumbai Mein", logline: "")
        ctx.insert(p)
        let ep = Episode(title: "Arrival", order: 0)
        ep.project = p
        p.episodes.append(ep)
        ctx.insert(ep)
        let scene = ScriptScene(
            locationName: "MUMBAI LOCAL TRAIN",
            location: .interior,
            time: .night,
            order: 0
        )
        scene.episode = ep
        ep.scenes.append(scene)
        ctx.insert(scene)
        let line = SceneElement(
            kind: .action,
            text: "The carriage is half empty. Rain streaks the window.",
            order: 0
        )
        line.scene = scene
        scene.elements.append(line)
        ctx.insert(line)
        return p
    }

    // MARK: - Auto color / round

    @Test func firstSaveIsWhiteRoundOne() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let out = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        )
        #expect(out.revision.color == .white)
        #expect(out.revision.roundNumber == 1)
    }

    @Test func secondSaveAdvancesToBlue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        _ = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        )
        let out2 = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        )
        #expect(out2.revision.color == .blue)
        #expect(out2.revision.roundNumber == 2)
    }

    @Test func roundNumberMonotonicAcrossWraparound() throws {
        // Save 3 revisions. Color advances white → blue → pink. Round
        // advances 1 → 2 → 3 regardless of color wrapping.
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        var rounds: [Int] = []
        for _ in 0..<3 {
            let out = try SaveRevisionService.save(
                .init(authorName: "Rudra"),
                project: project,
                context: ctx
            )
            rounds.append(out.revision.roundNumber)
        }
        #expect(rounds == [1, 2, 3])
    }

    // MARK: - Overrides

    @Test func explicitColorOverridesAutoPick() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let out = try SaveRevisionService.save(
            .init(color: .pink, authorName: "Rudra"),
            project: project,
            context: ctx
        )
        #expect(out.revision.color == .pink)
    }

    @Test func explicitRoundNumberOverrides() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let out = try SaveRevisionService.save(
            .init(roundNumber: 42, authorName: "Rudra"),
            project: project,
            context: ctx
        )
        #expect(out.revision.roundNumber == 42)
    }

    @Test func explicitLabelOverridesDefault() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let out = try SaveRevisionService.save(
            .init(label: "Production draft", authorName: "Rudra"),
            project: project,
            context: ctx
        )
        #expect(out.revision.label == "Production draft")
    }

    @Test func defaultLabelIsColorRevision() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let out = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        )
        // First revision is White → "White revision".
        #expect(out.revision.label == "White revision")
    }

    @Test func defaultLabelHelperFormatsCorrectly() {
        #expect(SaveRevisionService.defaultLabel(for: .pink) == "Pink revision")
        #expect(
            SaveRevisionService.defaultLabel(for: .doubleCherry)
                == "Double Cherry revision"
        )
    }

    // MARK: - Snapshot

    @Test func snapshotIsFountainExportOfProject() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let out = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        )
        let expected = FountainExporter.export(project: project)
        #expect(out.revision.fountainSnapshot == expected)
        #expect(out.snapshotBytes == expected.utf8.count)
    }

    @Test func snapshotsReflectContentChangesBetweenSaves() throws {
        // Real-world workflow: save a revision, mutate the project,
        // save again. The two snapshots MUST differ — otherwise the
        // whole revision system is theatre.
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let r1 = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        ).revision

        // Mutate — add a new action element to the first scene, just
        // like a writer would after the first revision.
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!
        let newLine = SceneElement(
            kind: .action,
            text: "Arjun looks past her at the platform sliding into view.",
            order: scene.elements.count
        )
        newLine.scene = scene
        scene.elements.append(newLine)
        ctx.insert(newLine)
        try ctx.save()

        let r2 = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        ).revision

        let marker = "Arjun looks past her at the platform sliding into view."
        #expect(r1.fountainSnapshot != r2.fountainSnapshot)
        #expect(r2.fountainSnapshot.contains(marker))
        #expect(!r1.fountainSnapshot.contains(marker))
        // And the colour + round advance correctly.
        #expect(r2.color == .blue)
        #expect(r2.roundNumber == 2)
    }

    @Test func snapshotsRoundTripFiveTimesWithDistinctEdits() throws {
        // Mirrors the manual five-save validation in the running Mac
        // app, but with a different edit between every save so we
        // can prove every snapshot is distinct (and that round
        // numbers + colours march in lockstep).
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!

        var snapshots: [String] = []
        var colours: [RevisionColor] = []
        var rounds: [Int] = []
        for i in 0..<5 {
            let line = SceneElement(
                kind: .action,
                text: "Edit \(i + 1).",
                order: scene.elements.count
            )
            line.scene = scene
            scene.elements.append(line)
            ctx.insert(line)
            try ctx.save()

            let out = try SaveRevisionService.save(
                .init(authorName: "Rudra"),
                project: project,
                context: ctx
            )
            snapshots.append(out.revision.fountainSnapshot)
            colours.append(out.revision.color)
            rounds.append(out.revision.roundNumber)
        }

        #expect(Set(snapshots).count == 5)
        #expect(colours == [.white, .blue, .pink, .yellow, .green])
        #expect(rounds == [1, 2, 3, 4, 5])
        // Each later snapshot includes ALL earlier marker lines.
        for i in 1..<5 {
            #expect(snapshots[i].contains("Edit \(i + 1)."))
            #expect(snapshots[i].contains("Edit \(i)."))
        }
    }

    @Test func snapshotIsNonEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let out = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        )
        #expect(!out.revision.fountainSnapshot.isEmpty)
        #expect(out.snapshotBytes > 0)
    }

    // MARK: - Author

    @Test func authorNameStampedOnRow() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let out = try SaveRevisionService.save(
            .init(authorName: "Rudra Pratap Singh"),
            project: project,
            context: ctx
        )
        #expect(out.revision.authorName == "Rudra Pratap Singh")
    }

    @Test func blankAuthorThrows() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        #expect(throws: SaveRevisionService.Error.blankAuthor) {
            try SaveRevisionService.save(
                .init(authorName: "   "),
                project: project,
                context: ctx
            )
        }
    }

    // MARK: - Persistence

    @Test func revisionAttachedAndCounted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        #expect(project.revisions.isEmpty)
        _ = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        )
        #expect(project.revisions.count == 1)
        #expect(project.activeRevision?.color == .white)
    }

    @Test func sceneCountAndWordCountSnapshotted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let out = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        )
        #expect(out.revision.sceneCountAtSave == 1)
        #expect(out.revision.wordCountAtSave > 0)
    }

    // MARK: - Element stamping

    @Test func stampElementSetsLastRevisedToActiveRevisionID() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let element = project.activeEpisodesOrdered.first!
            .scenesOrdered.first!.elementsOrdered.first!

        // Save a revision first so there's an active one.
        let out = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        )
        #expect(element.lastRevisedRevisionID == nil)

        SaveRevisionService.stampElementAsEdited(element, in: project)
        #expect(element.lastRevisedRevisionID == out.revision.id)
    }

    @Test func stampElementNoOpWhenNoActiveRevision() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let element = project.activeEpisodesOrdered.first!
            .scenesOrdered.first!.elementsOrdered.first!

        SaveRevisionService.stampElementAsEdited(element, in: project)
        #expect(element.lastRevisedRevisionID == nil)
    }

    @Test func stampingSecondTimeMovesIDForward() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let element = project.activeEpisodesOrdered.first!
            .scenesOrdered.first!.elementsOrdered.first!

        let r1 = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        ).revision
        SaveRevisionService.stampElementAsEdited(element, in: project)
        #expect(element.lastRevisedRevisionID == r1.id)

        let r2 = try SaveRevisionService.save(
            .init(authorName: "Rudra"),
            project: project,
            context: ctx
        ).revision
        SaveRevisionService.stampElementAsEdited(element, in: project)
        #expect(element.lastRevisedRevisionID == r2.id)
    }

    // MARK: - approximateWordCount helper

    @Test func wordCountSplitsOnWhitespace() {
        #expect(SaveRevisionService.approximateWordCount(in: "") == 0)
        #expect(SaveRevisionService.approximateWordCount(in: "one") == 1)
        #expect(SaveRevisionService.approximateWordCount(in: "one two three") == 3)
        #expect(
            SaveRevisionService.approximateWordCount(in: "one\ntwo\nthree") == 3
        )
    }
}
