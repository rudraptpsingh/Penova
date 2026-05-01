//
//  FountainImporterRoundTripTests.swift
//  PenovaTests
//
//  v1.2 Phase 2 — proves the full Project → Fountain → Project loop
//  preserves Penova-namespaced metadata that the parser collected and
//  the importer now writes back to the SwiftData model.
//
//  Phase 1 (PenovaFountainDialectTests) pinned the parser/exporter
//  contract: round-trip via the lightweight ParsedDocument shape.
//  Phase 2 closes the loop: parsed metadata actually lands on the
//  Project / ScriptScene rows when re-imported.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration(
        "FountainImporterRoundTripTests",
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
@Suite struct FountainImporterRoundTripTests {

    // MARK: - Genre + status round-trip

    @Test func genreAndStatusRoundTripThroughImporter() throws {
        let container = try makeContainer()
        let original = Project(
            title: "Round-Trip",
            logline: "A robot learns to feel.",
            genre: [.sciFi, .drama],
            status: .archived
        )
        container.mainContext.insert(original)

        let fountain = FountainExporter.export(project: original)
        let parsed = FountainParser.parse(fountain)
        let imported = FountainImporter.makeProject(
            title: original.title,
            from: parsed,
            context: container.mainContext
        )

        #expect(imported.title == "Round-Trip")
        #expect(imported.genre.contains(.sciFi))
        #expect(imported.genre.contains(.drama))
        #expect(imported.status == .archived)
        #expect(imported.logline == "A robot learns to feel.")
    }

    // MARK: - Locked-state round-trip

    @Test func lockedStateRoundTripsThroughImporter() throws {
        let container = try makeContainer()
        let original = Project(title: "Locked Pilot")
        container.mainContext.insert(original)

        let episode = Episode(title: "Pilot", order: 0)
        episode.project = original
        original.episodes.append(episode)
        container.mainContext.insert(episode)

        for i in 0..<3 {
            let scene = ScriptScene(locationName: "LOC \(i)", order: i)
            scene.episode = episode
            episode.scenes.append(scene)
            container.mainContext.insert(scene)
        }

        original.lock()
        let originalLockedNumbers = original.lockedSceneNumbers
        let originalLockedAt = original.lockedAt

        let fountain = FountainExporter.export(project: original)
        let parsed = FountainParser.parse(fountain)
        let imported = FountainImporter.makeProject(
            title: original.title,
            from: parsed,
            context: container.mainContext
        )

        #expect(imported.locked == true)
        #expect(imported.lockedAt != nil)
        #expect(imported.lockedSceneNumbers != nil)
        // The map should be byte-for-byte (sorted JSON encoding).
        #expect(imported.lockedSceneNumbers == originalLockedNumbers)
        // ISO8601 round-trip with fractional seconds preserves to ms.
        if let lock = originalLockedAt, let imLock = imported.lockedAt {
            #expect(abs(lock.timeIntervalSince(imLock)) < 0.001)
        }
    }

    // MARK: - Scene meta round-trip via importer

    @Test func sceneMetaRoundTripsThroughImporter() throws {
        let container = try makeContainer()
        let original = Project(title: "Beats")
        container.mainContext.insert(original)

        let episode = Episode(title: "Pilot", order: 0)
        episode.project = original
        original.episodes.append(episode)
        container.mainContext.insert(episode)

        let scene1 = ScriptScene(locationName: "OPENING", order: 0)
        scene1.episode = episode
        scene1.beatType = .setup
        scene1.actNumber = 1
        episode.scenes.append(scene1)
        container.mainContext.insert(scene1)

        let scene2 = ScriptScene(locationName: "CLIMAX", order: 1)
        scene2.episode = episode
        scene2.beatType = .climax
        scene2.actNumber = 3
        scene2.bookmarked = true
        episode.scenes.append(scene2)
        container.mainContext.insert(scene2)

        let fountain = FountainExporter.export(project: original)
        let parsed = FountainParser.parse(fountain)
        let imported = FountainImporter.makeProject(
            title: original.title,
            from: parsed,
            context: container.mainContext
        )

        let scenes = imported.episodes.first?.scenes.sorted { $0.order < $1.order } ?? []
        #expect(scenes.count == 2)
        #expect(scenes[0].beatType == .setup)
        #expect(scenes[0].actNumber == 1)
        #expect(scenes[0].bookmarked == false)
        #expect(scenes[1].beatType == .climax)
        #expect(scenes[1].actNumber == 3)
        #expect(scenes[1].bookmarked == true)
    }

    // MARK: - Title-page extensions land on imported titlePage

    @Test func titlePageExtensionsRoundTripThroughImporter() throws {
        let container = try makeContainer()
        let original = Project(title: "Production Draft")
        original.titlePage = TitlePage(
            title: "Production Draft",
            credit: "Story by",
            author: "Rudra Pratap Singh",
            source: "Based on a true event.",
            draftDate: "1 May 2026",
            draftStage: "Production Draft",
            contact: "rudra@example.com\n+91 99563 40651",
            copyright: "© 2026 Rudra Pratap Singh",
            notes: "Studio circulation copy."
        )
        container.mainContext.insert(original)

        let fountain = FountainExporter.export(project: original)
        let parsed = FountainParser.parse(fountain)
        let imported = FountainImporter.makeProject(
            title: original.title,
            from: parsed,
            context: container.mainContext
        )

        let tp = imported.titlePage
        #expect(tp.title == "Production Draft")
        #expect(tp.credit == "Story by")
        #expect(tp.author == "Rudra Pratap Singh")
        #expect(tp.source == "Based on a true event.")
        #expect(tp.draftDate == "1 May 2026")
        #expect(tp.draftStage == "Production Draft")
        #expect(tp.contact.contains("rudra@example.com"))
        #expect(tp.contact.contains("99563 40651"))
        #expect(tp.copyright == "© 2026 Rudra Pratap Singh")
        #expect(tp.notes == "Studio circulation copy.")
    }

    // MARK: - Multi-episode round-trip

    @Test func multiEpisodeProjectRoundTripsScenes() throws {
        let container = try makeContainer()
        let original = Project(title: "Series")
        container.mainContext.insert(original)

        for (i, name) in ["Pilot", "Episode 2"].enumerated() {
            let ep = Episode(title: name, order: i)
            ep.project = original
            original.episodes.append(ep)
            container.mainContext.insert(ep)
            let scene = ScriptScene(locationName: "LOC \(i)", order: 0)
            scene.episode = ep
            ep.scenes.append(scene)
            container.mainContext.insert(scene)
        }

        let fountain = FountainExporter.export(project: original)
        let parsed = FountainParser.parse(fountain)
        let imported = FountainImporter.makeProject(
            title: original.title,
            from: parsed,
            context: container.mainContext
        )
        // Importer currently flattens to a single "Pilot" episode; the
        // scene count should still match the source. Multi-episode
        // round-trip is documented in the spec but FountainImporter
        // hasn't been extended to honor /* Penova-Episode: */ yet —
        // future Phase 2 task.
        let totalScenes = imported.episodes.reduce(0) { $0 + $1.scenes.count }
        #expect(totalScenes == 2)
    }

    // MARK: - Round-trip stability (structural, not byte-equivalent)
    //
    // The spec (§Test contract) promises *structural* equivalence after
    // a round-trip — not byte-equivalence. Byte-equivalence is hard to
    // hit because the exporter pulls the signed-in user's name from
    // UserDefaults as an author fallback; that field can be empty on
    // first export and populated on second export after the import
    // captured the value into the model. Phase 3 will tighten this to
    // strict byte-equivalence once the exporter stops reading
    // UserDefaults; for now we assert the things that matter for
    // portability.

    @Test func roundTripPreservesStructuralFields() throws {
        let container = try makeContainer()
        let original = Project(
            title: "Idempotent",
            logline: "A test of round-trip stability.",
            genre: [.thriller],
            status: .active
        )
        container.mainContext.insert(original)

        let episode = Episode(title: "Pilot", order: 0)
        episode.project = original
        original.episodes.append(episode)
        container.mainContext.insert(episode)

        let scene = ScriptScene(locationName: "ROOFTOP", order: 0)
        scene.episode = episode
        scene.beatType = .midpoint
        scene.actNumber = 2
        episode.scenes.append(scene)
        container.mainContext.insert(scene)

        let exported = FountainExporter.export(project: original)
        let parsed = FountainParser.parse(exported)
        let imported = FountainImporter.makeProject(
            title: original.title,
            from: parsed,
            context: container.mainContext
        )

        #expect(imported.title == original.title)
        #expect(imported.logline == original.logline)
        #expect(imported.genre == original.genre)
        #expect(imported.status == original.status)

        let importedScene = imported.episodes.first?.scenes.first
        #expect(importedScene?.locationName == "ROOFTOP")
        #expect(importedScene?.beatType == .midpoint)
        #expect(importedScene?.actNumber == 2)
    }

    // MARK: - Forward-compat: unknown Penova- keys preserved

    @Test func unknownPenovaTitleKeySurvivesParsing() {
        let synthetic = """
        Title: Forward Compat
        Penova-Future-Field: someValue

        INT. ROOM - DAY

        Action.
        """
        let parsed = FountainParser.parse(synthetic)
        // The unknown key is preserved on ParsedDocument; even though
        // FountainImporter doesn't apply it to a model field today,
        // it survives the parse so a Penova v1.3 reader could write
        // back exactly what was loaded.
        #expect(parsed.titlePage["penova-future-field"] == "someValue")
    }
}
