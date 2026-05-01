//
//  ProductionReportsTests.swift
//  PenovaTests
//
//  Pins the contract for scene / location / cast production reports.
//  These tables drive pre-production downstream of a "locked" script
//  (casting, scheduling, location scouting); silent regressions break
//  trust with line producers and ADs.
//

import Testing
import Foundation
import SwiftData
@testable import Penova
@testable import PenovaKit

@MainActor
@Suite struct ProductionReportsTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self,
            SceneElement.self, ScriptCharacter.self, WritingDay.self,
            configurations: config
        )
    }

    private func newScene(
        in ep: Episode, ctx: ModelContext,
        location: String, kind: SceneLocation = .interior, time: SceneTimeOfDay = .day,
        elements: [(SceneElementKind, String)]
    ) -> ScriptScene {
        let s = ScriptScene(locationName: location, location: kind, time: time,
                            order: ep.scenes.count)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        for (i, pair) in elements.enumerated() {
            let el = SceneElement(kind: pair.0, text: pair.1, order: i)
            el.scene = s; s.elements.append(el); ctx.insert(el)
        }
        return s
    }

    private func makeFixtureProject(in ctx: ModelContext) throws -> Project {
        let p = Project(title: "Fixture"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        _ = newScene(in: ep, ctx: ctx, location: "Bar", kind: .interior, time: .night, elements: [
            (.heading, "INT. BAR - NIGHT"),
            (.action, "Smoke."),
            (.character, "ALICE"), (.dialogue, "I quit."),
            (.character, "BOB"),   (.dialogue, "Don't."),
        ])
        _ = newScene(in: ep, ctx: ctx, location: "Marine Drive", kind: .exterior, time: .evening, elements: [
            (.heading, "EXT. MARINE DRIVE - EVENING"),
            (.character, "ALICE"), (.dialogue, "It's cold."),
            (.character, "ALICE (CONT'D)"), (.dialogue, "Always cold."),
        ])
        _ = newScene(in: ep, ctx: ctx, location: "Bar", kind: .interior, time: .night, elements: [
            (.heading, "INT. BAR - NIGHT"),
            (.action, "Empty."),
            (.character, "BOB"), (.dialogue, "Anyone here?"),
        ])
        try ctx.save()
        return p
    }

    // MARK: - Scene report

    @Test func sceneReportRowPerScene() throws {
        let container = try makeContainer()
        let project = try makeFixtureProject(in: container.mainContext)
        let rows = ProductionReports.sceneReport(for: project)
        #expect(rows.count == 3, "expected 3 scenes; got \(rows.count)")
    }

    @Test func sceneReportNumberingResetsPerEpisodeWhenMultiple() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Two-Episode"); ctx.insert(p)
        for i in 0..<2 {
            let ep = Episode(title: "E\(i)", order: i); ep.project = p
            p.episodes.append(ep); ctx.insert(ep)
            _ = newScene(in: ep, ctx: ctx, location: "Loc\(i)A", elements: [(.heading, "INT. LOC\(i)A - DAY")])
            _ = newScene(in: ep, ctx: ctx, location: "Loc\(i)B", elements: [(.heading, "INT. LOC\(i)B - DAY")])
        }
        try ctx.save()
        let rows = ProductionReports.sceneReport(for: p)
        // Episode 0 → scenes 1, 2; Episode 1 → scenes 1, 2 (reset per episode).
        let perEp0 = rows.filter { $0.episodeOrder == 0 }.map(\.sceneNumber)
        let perEp1 = rows.filter { $0.episodeOrder == 1 }.map(\.sceneNumber)
        #expect(perEp0 == [1, 2])
        #expect(perEp1 == [1, 2])
    }

    @Test func sceneReportSingleEpisodeNumberingContinuous() throws {
        let container = try makeContainer()
        let project = try makeFixtureProject(in: container.mainContext)
        let rows = ProductionReports.sceneReport(for: project)
        #expect(rows.map(\.sceneNumber) == [1, 2, 3])
    }

    @Test func sceneReportCueAndWordCounts() throws {
        let container = try makeContainer()
        let project = try makeFixtureProject(in: container.mainContext)
        let rows = ProductionReports.sceneReport(for: project)
        // Scene 1 (Bar): heading + action ("Smoke.") + ALICE + "I quit." + BOB + "Don't."
        // distinct cues = 2 (ALICE, BOB)
        let scene1 = rows[0]
        #expect(scene1.cueCount == 2)
        // Dialogue words: "I quit." (2) + "Don't." (1) = 3
        #expect(scene1.dialogueWordCount == 3)
        // Total includes heading + action + cues + dialogue
        #expect(scene1.totalWordCount > scene1.dialogueWordCount)
    }

    // MARK: - Location report

    @Test func locationReportAggregatesAcrossScenes() throws {
        let container = try makeContainer()
        let project = try makeFixtureProject(in: container.mainContext)
        let rows = ProductionReports.locationReport(for: project)
        // BAR appears twice (scenes 1 + 3), MARINE DRIVE once.
        let bar = rows.first { $0.location == "BAR" }
        #expect(bar?.sceneCount == 2)
        let marine = rows.first { $0.location == "MARINE DRIVE" }
        #expect(marine?.sceneCount == 1)
    }

    @Test func locationReportSeparatesIntFromExt() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Indoor/Outdoor"); ctx.insert(p)
        let ep = Episode(title: "P", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        _ = newScene(in: ep, ctx: ctx, location: "Park", kind: .interior, elements: [(.heading, "INT. PARK")])
        _ = newScene(in: ep, ctx: ctx, location: "Park", kind: .exterior, elements: [(.heading, "EXT. PARK")])
        try ctx.save()
        let rows = ProductionReports.locationReport(for: p)
        // Same location string but different INT/EXT → two separate rows.
        let parkRows = rows.filter { $0.location == "PARK" }
        #expect(parkRows.count == 2)
        #expect(Set(parkRows.map(\.intExt)) == ["INT", "EXT"])
    }

    @Test func locationReportSortedByFrequency() throws {
        let container = try makeContainer()
        let project = try makeFixtureProject(in: container.mainContext)
        let rows = ProductionReports.locationReport(for: project)
        // BAR (2) before MARINE DRIVE (1).
        #expect(rows.first?.location == "BAR")
    }

    @Test func locationReportSkipsBlankLocations() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Blank"); ctx.insert(p)
        let ep = Episode(title: "P", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        _ = newScene(in: ep, ctx: ctx, location: "", elements: [])
        _ = newScene(in: ep, ctx: ctx, location: "  ", elements: [])
        _ = newScene(in: ep, ctx: ctx, location: "Real", elements: [])
        try ctx.save()
        let rows = ProductionReports.locationReport(for: p)
        #expect(rows.count == 1)
        #expect(rows.first?.location == "REAL")
    }

    // MARK: - Cast report

    @Test func castReportAggregatesDialogueAcrossScenes() throws {
        let container = try makeContainer()
        let project = try makeFixtureProject(in: container.mainContext)
        let rows = ProductionReports.castReport(for: project)
        let alice = rows.first { $0.name == "ALICE" }
        // Two scenes, three dialogue blocks (one with CONT'D suffix folded in).
        #expect(alice?.dialogueBlockCount == 3,
                "expected 3 ALICE dialogue blocks, got \(alice?.dialogueBlockCount ?? -1)")
        #expect(alice?.sceneAppearances == 2)
    }

    @Test func castReportFoldsContDSuffixIntoBaseName() throws {
        let container = try makeContainer()
        let project = try makeFixtureProject(in: container.mainContext)
        let rows = ProductionReports.castReport(for: project)
        // No "ALICE (CONT'D)" should appear as a separate row.
        #expect(!rows.contains { $0.name.contains("CONT") },
                "CONT'D not stripped; got \(rows.map(\.name))")
    }

    @Test func castReportSortedByDialogueWords() throws {
        let container = try makeContainer()
        let project = try makeFixtureProject(in: container.mainContext)
        let rows = ProductionReports.castReport(for: project)
        // ALICE has more total dialogue words than BOB → first.
        #expect(rows.first?.name == "ALICE",
                "expected ALICE first (most words); got \(rows.map(\.name))")
    }

    @Test func castReportEmptyForProjectWithNoDialogue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Silent"); ctx.insert(p)
        let ep = Episode(title: "E", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        _ = newScene(in: ep, ctx: ctx, location: "Beach", elements: [
            (.heading, "EXT. BEACH"),
            (.action, "Waves."),
        ])
        try ctx.save()
        let rows = ProductionReports.castReport(for: p)
        #expect(rows.isEmpty,
                "no character cues → no cast rows; got \(rows)")
    }
}
