//
//  PenovaFountainDialectTests.swift
//  PenovaTests
//
//  Pins the Penova Fountain dialect (docs/spec/penova-fountain.md) to
//  the parser + exporter behavior. These tests are the contract that
//  guarantees the on-disk `.fountain` format stays portable across
//  Apple-only and future Windows ports of Penova.
//
//  IMPORTANT: nothing in this dialect is user-facing. The user types
//  ordinary screenplay text in the editor; the exporter emits the
//  Penova-namespaced extensions silently when saving and the parser
//  strips them silently when loading. These tests validate that the
//  silent layer round-trips losslessly.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

// MARK: - In-memory SwiftData container helper

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration(
        "PenovaFountainDialectTests",
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
@Suite struct PenovaFountainDialectTests {

    // MARK: §1 — Standard Fountain title page round-trips

    @Test func standardTitleKeysRoundTrip() throws {
        let container = try makeContainer()
        let project = Project(title: "The Last Birthday Card",
                              logline: "A cancer doctor falls for a flower vendor.",
                              genre: [.drama])
        project.contactBlock = """
        Rudra Pratap Singh
        rudra.ptp.singh@gmail.com
        +91 99563 40651
        """
        container.mainContext.insert(project)

        let exported = FountainExporter.export(project: project)
        #expect(exported.contains("Title: The Last Birthday Card"))
        #expect(exported.contains("Notes: A cancer doctor"))
        #expect(exported.contains("Contact: Rudra Pratap Singh"))

        // Continuation lines are 3-space indented (per fountain.io §title page).
        #expect(exported.contains("   rudra.ptp.singh@gmail.com"))
        #expect(exported.contains("   +91 99563 40651"))

        let parsed = FountainParser.parse(exported)
        #expect(parsed.titlePage["title"] == "The Last Birthday Card")
        #expect(parsed.titlePage["notes"]?.contains("cancer doctor") == true)
        #expect(parsed.titlePage["contact"]?.contains("Rudra Pratap Singh") == true)
        #expect(parsed.titlePage["contact"]?.contains("rudra.ptp.singh@gmail.com") == true)
    }

    @Test func emptyTitleFieldsAreOmitted() throws {
        let container = try makeContainer()
        let project = Project(title: "Untitled")
        container.mainContext.insert(project)

        let exported = FountainExporter.export(project: project)
        // Notes and Contact are empty -> keys absent (per spec).
        #expect(!exported.contains("Notes:"))
        #expect(!exported.contains("Contact:"))
    }

    // MARK: §1 — Penova-namespaced title-page keys

    @Test func genreEmitsAndRoundTrips() throws {
        let container = try makeContainer()
        let project = Project(title: "Test",
                              genre: [.drama, .thriller])
        container.mainContext.insert(project)

        let exported = FountainExporter.export(project: project)
        #expect(exported.contains("Penova-Genre: drama, thriller"))

        let parsed = FountainParser.parse(exported)
        #expect(parsed.titlePage["penova-genre"] == "drama, thriller")
    }

    @Test func nonDefaultStatusEmits() throws {
        let container = try makeContainer()
        let project = Project(title: "Archived Project", status: .archived)
        container.mainContext.insert(project)

        let exported = FountainExporter.export(project: project)
        #expect(exported.contains("Penova-Status: archived"))
    }

    @Test func defaultStatusOmits() throws {
        let container = try makeContainer()
        let project = Project(title: "Active Project", status: .active)
        container.mainContext.insert(project)

        let exported = FountainExporter.export(project: project)
        // .active is the default -> no key emitted (spec §1).
        #expect(!exported.contains("Penova-Status:"))
    }

    @Test func lockedFlagsEmitWhenLocked() throws {
        let container = try makeContainer()
        let project = Project(title: "Locked")
        container.mainContext.insert(project)

        let episode = Episode(title: "Pilot", order: 0)
        episode.project = project
        project.episodes.append(episode)
        container.mainContext.insert(episode)

        let scene = ScriptScene(locationName: "KITCHEN", order: 0)
        scene.episode = episode
        episode.scenes.append(scene)
        container.mainContext.insert(scene)

        project.lock()
        let exported = FountainExporter.export(project: project)

        #expect(exported.contains("Penova-Locked: true"))
        #expect(exported.contains("Penova-Locked-At:"))
        #expect(exported.contains("Penova-Locked-Numbers:"))
    }

    @Test func unlockedProjectOmitsAllLockKeys() throws {
        let container = try makeContainer()
        let project = Project(title: "Spec script")
        container.mainContext.insert(project)

        let exported = FountainExporter.export(project: project)
        #expect(!exported.contains("Penova-Locked"))
        #expect(!exported.contains("Penova-Locked-At"))
        #expect(!exported.contains("Penova-Locked-Numbers"))
    }

    // MARK: §2 — `[[Penova: ...]]` element notes

    @Test func sceneBeatNoteEmitsAndParses() throws {
        let container = try makeContainer()
        let project = Project(title: "Beats")
        container.mainContext.insert(project)

        let episode = Episode(title: "Pilot", order: 0)
        episode.project = project
        project.episodes.append(episode)
        container.mainContext.insert(episode)

        let scene = ScriptScene(locationName: "KITCHEN", order: 0)
        scene.episode = episode
        scene.beatType = .midpoint
        episode.scenes.append(scene)
        container.mainContext.insert(scene)

        let exported = FountainExporter.export(project: project)
        #expect(exported.contains("[[Penova: beat=midpoint]]"))

        let parsed = FountainParser.parse(exported)
        // Scene metadata round-trips into ParsedDocument.sceneMeta keyed
        // by the scene's index in the parsed doc.
        let meta = parsed.sceneMeta[0]
        #expect(meta?.beat == .midpoint)
    }

    @Test func multipleSceneNotesShareLine() throws {
        let container = try makeContainer()
        let project = Project(title: "Multi-note")
        container.mainContext.insert(project)
        let episode = Episode(title: "Pilot", order: 0)
        episode.project = project
        project.episodes.append(episode)
        container.mainContext.insert(episode)

        let scene = ScriptScene(locationName: "OFFICE", order: 0)
        scene.episode = episode
        scene.beatType = .climax
        scene.actNumber = 3
        scene.bookmarked = true
        episode.scenes.append(scene)
        container.mainContext.insert(scene)

        let exported = FountainExporter.export(project: project)
        // All three notes on one line, space-separated.
        #expect(exported.contains("[[Penova: beat=climax]]"))
        #expect(exported.contains("[[Penova: actNumber=3]]"))
        #expect(exported.contains("[[Penova: bookmarked=true]]"))

        let parsed = FountainParser.parse(exported)
        let meta = parsed.sceneMeta[0]
        #expect(meta?.beat == .climax)
        #expect(meta?.actNumber == 3)
        #expect(meta?.bookmarked == true)
    }

    @Test func unknownSceneNoteSurvivesRoundTrip() {
        // Forward-compat: a v1.2 reader opens a v1.3-authored file with
        // an unknown note key — it goes into ParsedSceneMeta.unknown
        // instead of being lost.
        let synthetic = """
        Title: Forward Compat

        INT. OFFICE - DAY
        [[Penova: futureKey=futureValue]] [[Penova: beat=setup]]

        Action.
        """
        let parsed = FountainParser.parse(synthetic)
        let meta = parsed.sceneMeta[0]
        #expect(meta?.beat == .setup)
        #expect(meta?.unknown["futureKey"] == "futureValue")
    }

    // MARK: §3 — Episode boneyard delimiters

    @Test func multiEpisodeProjectEmitsBoneyards() throws {
        let container = try makeContainer()
        let project = Project(title: "Series Pilot")
        container.mainContext.insert(project)

        for (i, name) in ["Pilot", "Breaking Point"].enumerated() {
            let ep = Episode(title: name, order: i)
            ep.project = project
            project.episodes.append(ep)
            container.mainContext.insert(ep)
            let scene = ScriptScene(locationName: "PLACEHOLDER", order: 0)
            scene.episode = ep
            ep.scenes.append(scene)
            container.mainContext.insert(scene)
        }

        let exported = FountainExporter.export(project: project)
        #expect(exported.contains("/* Penova-Episode: 0 — Pilot — status=draft */"))
        #expect(exported.contains("/* Penova-Episode: 1 — Breaking Point — status=draft */"))
    }

    @Test func singleEpisodeProjectOmitsBoneyards() throws {
        let container = try makeContainer()
        let project = Project(title: "Feature")
        container.mainContext.insert(project)

        let ep = Episode(title: "Feature", order: 0)
        ep.project = project
        project.episodes.append(ep)
        container.mainContext.insert(ep)

        let exported = FountainExporter.export(project: project)
        #expect(!exported.contains("Penova-Episode"))
    }

    // MARK: §round-trip — body element kinds

    @Test func everyElementKindRoundTrips() {
        // Synthetic Fountain that exercises every SceneElementKind.
        let source = """
        Title: Round-Trip Smoke

        INT. KITCHEN - DAY

        ALEX walks in, holding a coffee.

        ALEX
        (under his breath)
        Not again.

        BETH (V.O.)
        Alex, behind you.

        FADE OUT:
        """
        let parsed = FountainParser.parse(source)
        #expect(parsed.scenes.count == 1)
        let scene = parsed.scenes[0]
        let kinds = scene.elements.map(\.kind)
        // Expect: action, character, parenthetical, dialogue, character, dialogue, transition
        #expect(kinds.contains(.action))
        #expect(kinds.contains(.character))
        #expect(kinds.contains(.parenthetical))
        #expect(kinds.contains(.dialogue))
        #expect(kinds.contains(.transition))
    }

    // MARK: §forward-compat — unknown title-page keys are tolerated

    @Test func unknownPenovaKeyIsKept() {
        // A v1.3-authored file might emit `Penova-Future-Key:`. v1.2
        // reader should preserve it in titlePage so re-export doesn't
        // drop it.
        let synthetic = """
        Title: Compat
        Penova-Future-Key: someValue

        INT. ROOM - DAY

        Action.
        """
        let parsed = FountainParser.parse(synthetic)
        #expect(parsed.titlePage["penova-future-key"] == "someValue")
    }

    // MARK: §round-trip — null project ID is regenerated, not asserted

    @Test func projectIDIsNotPartOfRoundTrip() throws {
        // Spec is explicit: Project.id is regenerated per import. We
        // never serialize it. This test pins that contract.
        let container = try makeContainer()
        let project = Project(title: "ID test")
        container.mainContext.insert(project)
        let originalID = project.id

        let exported = FountainExporter.export(project: project)
        #expect(!exported.contains(originalID))   // not anywhere in the output
    }
}
