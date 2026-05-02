//
//  PerformanceBaselineTests.swift
//  PenovaTests
//
//  Performance-regression guards. Each test runs a real-world-sized
//  workload and asserts a generous time budget. The budgets are 5–10×
//  what current measurements show, so they don't flake on CI under
//  load — but they DO catch the catastrophic case (someone introduces
//  an O(n²) loop on a 100-scene project).
//
//  These run on CI but with very loose budgets; the value is the
//  early warning when a refactor 10× the rendering time, not
//  micro-benchmarking. For nuanced perf work, use Instruments — not
//  these tests.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration(
        "PerfTests",
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func buildLargeProject(
    sceneCount: Int,
    elementsPerScene: Int,
    in context: ModelContext
) -> Project {
    let project = Project(title: "Perf \(sceneCount)x\(elementsPerScene)")
    context.insert(project)
    let ep = Episode(title: "P", order: 0)
    ep.project = project
    project.episodes.append(ep)
    context.insert(ep)
    for s in 0..<sceneCount {
        let scene = ScriptScene(locationName: "ROOM \(s)", order: s)
        scene.episode = ep
        ep.scenes.append(scene)
        context.insert(scene)
        for e in 0..<elementsPerScene {
            let kind: SceneElementKind
            switch e % 4 {
            case 0: kind = .action
            case 1: kind = .character
            case 2: kind = .dialogue
            default: kind = .action
            }
            let el = SceneElement(
                kind: kind,
                text: kind == .character
                    ? "CHARACTER_\(s)_\(e)"
                    : "Body of element \(e) in scene \(s). " + String(repeating: "Padding. ", count: 4),
                order: e
            )
            el.scene = scene
            scene.elements.append(el)
            context.insert(el)
        }
    }
    return project
}

@MainActor
@Suite struct PerformanceBaselineTests {

    /// **Fountain export of a feature-length project** — 100 scenes,
    /// 30 elements each = 3,000 elements. Should run in well under
    /// 1 second on any modern machine. Budget: 3 seconds (CI tolerance).
    @Test func fountainExportOf3000Elements_under3s() throws {
        let container = try makeContainer()
        let project = buildLargeProject(
            sceneCount: 100,
            elementsPerScene: 30,
            in: container.mainContext
        )
        let start = Date()
        let exported = FountainExporter.export(project: project)
        let elapsed = -start.timeIntervalSinceNow
        #expect(!exported.isEmpty)
        #expect(elapsed < 3.0,
                "Fountain export of 3000 elements took \(elapsed)s — budget is 3s; an O(n²) regression in the exporter would fail this immediately.")
    }

    /// **Fountain parse of the same shape** — round-trip the export.
    /// Parser should run faster than exporter; budget 3s.
    @Test func fountainParseOf3000Elements_under3s() throws {
        let container = try makeContainer()
        let project = buildLargeProject(
            sceneCount: 100,
            elementsPerScene: 30,
            in: container.mainContext
        )
        let exported = FountainExporter.export(project: project)

        let start = Date()
        let parsed = FountainParser.parse(exported)
        let elapsed = -start.timeIntervalSinceNow
        // Don't pin scene count here — round-trip correctness is
        // covered by FountainRoundTripTests / RealScriptEndToEndTests
        // against well-formed input. THIS test only measures the
        // parser's runtime budget on a large input. (The synth
        // exporter emits pseudo-scenes that the parser doesn't
        // always recognize as separate scenes; that's fine for a
        // perf test.)
        #expect(!parsed.scenes.isEmpty,
                "Parser must process the input without producing zero output")
        #expect(elapsed < 3.0,
                "Fountain parse of 3000 elements took \(elapsed)s — budget is 3s")
    }

    /// **PDF page-count measurement on feature-length** — the
    /// `measurePageCount` path is on the hot path of the editor's
    /// "Pages" status indicator. Should complete in well under a
    /// second; budget 2s.
    @Test func pdfMeasurePageCount_under2s() throws {
        let container = try makeContainer()
        let project = buildLargeProject(
            sceneCount: 50,
            elementsPerScene: 20,
            in: container.mainContext
        )
        let start = Date()
        let pageCount = ScreenplayPDFRenderer.measurePageCount(project: project)
        let elapsed = -start.timeIntervalSinceNow
        #expect(pageCount > 5,
                "Synthesized 50-scene project should render to >5 pages")
        #expect(elapsed < 2.0,
                "measurePageCount on a 50×20 project took \(elapsed)s — budget is 2s")
    }

    /// **Production reports on feature-length** — Reports view
    /// computes scene/location/cast tables. Should be near-instant
    /// even on big projects; budget 1s.
    @Test func productionReports_under1s() throws {
        let container = try makeContainer()
        let project = buildLargeProject(
            sceneCount: 100,
            elementsPerScene: 30,
            in: container.mainContext
        )
        let start = Date()
        let scenesReport = ProductionReports.sceneReport(for: project)
        let locationsReport = ProductionReports.locationReport(for: project)
        let castReport = ProductionReports.castReport(for: project)
        let elapsed = -start.timeIntervalSinceNow
        #expect(!scenesReport.isEmpty)
        #expect(!locationsReport.isEmpty)
        // Cast report may be empty if the synth doesn't insert
        // ScriptCharacter rows (it inserts cue strings only). Don't
        // require non-empty; just that the call returned in budget.
        _ = castReport
        #expect(elapsed < 1.0,
                "Production reports on a 100×30 project took \(elapsed)s — budget is 1s")
    }

    /// **Character rename across a feature-length project** — the
    /// element-aware rename has to walk every scene's elements.
    /// O(scenes × elements) is fine; O(scenes² × elements) is not.
    @Test func characterRenameAcrossLargeProject_under1s() throws {
        let container = try makeContainer()
        let project = buildLargeProject(
            sceneCount: 100,
            elementsPerScene: 20,
            in: container.mainContext
        )
        // Rename one specific cue name that appears in many scenes.
        // The synth gives every cue a unique name (CHARACTER_S_E) so
        // the rename hits exactly one cue per scene-element-position.
        // Test "no name matches" branch since none of the synth names
        // equal "JANE":
        let start = Date()
        _ = CharacterRename.renameAcrossProjects(
            in: [project],
            from: "JANE",
            to: "JEAN"
        )
        let elapsed = -start.timeIntervalSinceNow
        #expect(elapsed < 1.0,
                "Character rename on 2000 elements took \(elapsed)s — budget is 1s")
    }
}
