//
//  SmokeTest.swift
//  Penova for Mac
//
//  End-to-end smoke harness that drives every feature internally
//  (no Accessibility permission needed) and reports pass/fail to
//  stdout + OSLog. Triggered with the launch arg `--smoke`. Exits
//  with status 0 on all-pass, 1 on any failure.
//
//  Each scenario asserts a real user-visible invariant:
//    · sample library shape
//    · new-project flow creates Project + Episode + first Scene
//    · Tab/Enter element-type contract
//    · normalisation of caps/parens
//    · search by location, dialogue, character
//    · drag-reorder produces a 0..n-1 compact ordering
//    · Fountain export preserves canonical tokens
//    · FDX export emits expected paragraph types
//    · PDF export writes a valid PDF on disk that PDFKit can read
//    · scene insertion works against an existing episode
//    · model context save survives across fetches
//

import Foundation
import SwiftData
import PDFKit
import AppKit
import PenovaKit

enum SmokeTest {

    struct Failure: Error {
        let scenario: String
        let detail: String
    }

    /// Returns the number of failed scenarios. Caller exits with that
    /// number as the process status.
    @discardableResult
    static func run() -> Int {
        var passed = 0
        var failed = 0
        var report: [String] = []

        report.append("=== Penova Mac Smoke Test ===")
        report.append("Timestamp: \(Date())")

        let scenarios: [(name: String, body: (ModelContext) throws -> Void)] = [
            ("01 sample library shape", scenario_sampleLibrary),
            ("02 new-project flow",      scenario_newProject),
            ("03 tab/enter contract",    scenario_tabEnter),
            ("04 normalisation",         scenario_normalisation),
            ("05 search service",        scenario_search),
            ("06 drag reorder",          scenario_reorder),
            ("07 fountain export",       scenario_fountain),
            ("08 fdx export",            scenario_fdx),
            ("09 pdf export",            scenario_pdf),
            ("10 scene insertion",       scenario_sceneInsert),
            ("11 model save round-trip", scenario_modelSave),
        ]

        for (name, body) in scenarios {
            do {
                let ctx = try makeContext()
                try body(ctx)
                report.append("✔ \(name)")
                passed += 1
            } catch let f as Failure {
                report.append("✘ \(name) — \(f.detail)")
                failed += 1
            } catch {
                report.append("✘ \(name) — \(error.localizedDescription)")
                failed += 1
            }
        }

        report.append("")
        report.append("Result: \(passed) passed, \(failed) failed (of \(scenarios.count))")
        let text = report.joined(separator: "\n")
        print(text)
        PenovaLog.automation.notice("Smoke test result: \(passed, privacy: .public) passed, \(failed, privacy: .public) failed")
        return failed
    }

    private static func makeContext() throws -> ModelContext {
        let schema = Schema(PenovaSchema.models)
        let config = ModelConfiguration("smoke", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - Scenarios

    private static func scenario_sampleLibrary(_ ctx: ModelContext) throws {
        SampleLibrary.installIfNeeded(in: ctx)
        let projects = try ctx.fetch(FetchDescriptor<Project>())
        try assert(projects.count == 1, "expected 1 project, got \(projects.count)")
        let p = projects.first!
        try assert(p.title == "Ek Raat Mumbai Mein", "wrong title: \(p.title)")
        try assert(p.activeEpisodesOrdered.count == 2, "expected 2 episodes")
        let kitchen = p.activeEpisodesOrdered[1].scenesOrdered.first
        try assert(kitchen?.locationName == "KITCHEN", "missing kitchen scene")
        try assert(kitchen?.elementsOrdered.count == 18, "kitchen scene has \(kitchen?.elementsOrdered.count ?? 0) elements")
    }

    private static func scenario_newProject(_ ctx: ModelContext) throws {
        let p = Project(title: "Smoke Test Project", logline: "A test.", genre: [.drama])
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p
        ctx.insert(ep)
        let scene = ScriptScene(locationName: "TEST", location: .interior, time: .day, order: 0)
        scene.episode = ep
        ctx.insert(scene)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Project>())
        try assert(fetched.count == 1, "create+save+fetch round-trip lost the project")
        try assert(fetched.first?.activeEpisodesOrdered.first?.scenesOrdered.count == 1,
                   "new project should have one starter scene")
    }

    private static func scenario_tabEnter(_ ctx: ModelContext) throws {
        try assert(EditorLogic.nextKind(after: .heading) == .action, "heading→action")
        try assert(EditorLogic.nextKind(after: .character) == .dialogue, "character→dialogue")
        try assert(EditorLogic.nextKind(after: .dialogue) == .action, "dialogue→action")
        try assert(EditorLogic.nextKind(after: .parenthetical) == .dialogue, "paren→dialogue")
        try assert(EditorLogic.nextKind(after: .transition) == .heading, "transition→heading")
        // Tab cycles through allCases
        let order = SceneElementKind.allCases
        for (i, k) in order.enumerated() {
            let next = EditorLogic.tabCycle(from: k)
            try assert(next == order[(i + 1) % order.count], "tab cycle wrong from \(k)")
        }
    }

    private static func scenario_normalisation(_ ctx: ModelContext) throws {
        try assert(EditorLogic.normalise(text: "int. lab - day", kind: .heading)
                   == "INT. LAB - DAY", "heading uppercase")
        try assert(EditorLogic.normalise(text: "  sam  ", kind: .character)
                   == "SAM", "character trim+upper")
        try assert(EditorLogic.normalise(text: "without smile", kind: .parenthetical)
                   == "(without smile)", "auto-wrap parenthetical")
        try assert(EditorLogic.normalise(text: "(already)", kind: .parenthetical)
                   == "(already)", "preserve already-wrapped paren")
        try assert(EditorLogic.normalise(text: "Action stays cased.", kind: .action)
                   == "Action stays cased.", "action retains case")
    }

    private static func scenario_search(_ ctx: ModelContext) throws {
        SampleLibrary.installIfNeeded(in: ctx)
        let projects = try ctx.fetch(FetchDescriptor<Project>())

        let r1 = SearchService.search(query: "kitchen", in: projects)
        try assert(r1.contains { $0.kind == .scene && $0.title.contains("KITCHEN") },
                   "search 'kitchen' missing scene match")
        try assert(r1.contains { $0.kind == .location },
                   "search 'kitchen' missing location match")

        let r2 = SearchService.search(query: "I quit", in: projects)
        try assert(r2.contains { $0.kind == .dialogue },
                   "search 'I quit' missing dialogue match")

        let r3 = SearchService.search(query: "PENNY", in: projects)
        try assert(r3.contains { $0.kind == .character && $0.title == "PENNY" },
                   "search 'PENNY' missing character match")

        try assert(SearchService.search(query: "", in: projects).isEmpty,
                   "empty query should return no results")
    }

    private static func scenario_reorder(_ ctx: ModelContext) throws {
        SampleLibrary.installIfNeeded(in: ctx)
        let project = try ctx.fetch(FetchDescriptor<Project>()).first!
        let ep2 = project.activeEpisodesOrdered[1]
        let scenes = ep2.scenesOrdered
        let kitchen = scenes.first { $0.locationName == "KITCHEN" }!

        let items = scenes.map { (id: $0.id, order: $0.order) }
        let reordered = SceneReorder.move(items, movingID: kitchen.id, to: 0)
        try assert(reordered.first?.id == kitchen.id, "kitchen should be at index 0")
        try assert(reordered.map(\.order) == Array(0..<reordered.count),
                   "orders not compacted to 0..n-1: \(reordered.map(\.order))")
    }

    private static func scenario_fountain(_ ctx: ModelContext) throws {
        SampleLibrary.installIfNeeded(in: ctx)
        let project = try ctx.fetch(FetchDescriptor<Project>()).first!
        let text = FountainExporter.export(project: project)
        for token in ["INT. KITCHEN - NIGHT", "MARCUS", "PENNY", "(without turning)", "I quit today.", "CUT TO:"] {
            try assert(text.contains(token), "fountain missing '\(token)'")
        }
    }

    private static func scenario_fdx(_ ctx: ModelContext) throws {
        SampleLibrary.installIfNeeded(in: ctx)
        let project = try ctx.fetch(FetchDescriptor<Project>()).first!
        let xml = FinalDraftXMLWriter.xml(for: project)
        for marker in [
            "<FinalDraft DocumentType=\"Script\"",
            "<Paragraph Type=\"Scene Heading\"",
            "<Paragraph Type=\"Character\"",
            "<Paragraph Type=\"Dialogue\"",
            "<Paragraph Type=\"Action\"",
            "<Paragraph Type=\"Transition\"",
        ] {
            try assert(xml.contains(marker), "fdx missing '\(marker)'")
        }
    }

    private static func scenario_pdf(_ ctx: ModelContext) throws {
        SampleLibrary.installIfNeeded(in: ctx)
        let project = try ctx.fetch(FetchDescriptor<Project>()).first!

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("smoke-pdf-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try ScreenplayPDFRenderer.render(project: project, to: url)
        let data = try Data(contentsOf: url)
        try assert(data.count > 1024, "pdf too small: \(data.count) bytes")

        guard let pdf = PDFDocument(url: url) else {
            throw Failure(scenario: "pdf", detail: "PDFKit could not load the file")
        }
        try assert(pdf.pageCount >= 2, "expected ≥2 pages, got \(pdf.pageCount)")

        let extracted = pdf.string ?? ""
        try assert(extracted.contains("KITCHEN"), "pdf text missing KITCHEN")
        try assert(extracted.contains("PENNY"), "pdf text missing PENNY")
        try assert(extracted.contains("MARCUS"), "pdf text missing MARCUS")
    }

    private static func scenario_sceneInsert(_ ctx: ModelContext) throws {
        SampleLibrary.installIfNeeded(in: ctx)
        let project = try ctx.fetch(FetchDescriptor<Project>()).first!
        let ep = project.activeEpisodesOrdered.first!
        let beforeCount = ep.scenes.count

        let nextOrder = (ep.scenes.map(\.order).max() ?? -1) + 1
        let scene = ScriptScene(locationName: "INSERTED", location: .exterior, time: .dawn, order: nextOrder)
        scene.episode = ep
        ctx.insert(scene)
        try ctx.save()

        try assert(ep.scenes.count == beforeCount + 1, "scene count didn't grow")
        try assert(ep.scenesOrdered.last?.locationName == "INSERTED", "inserted scene not last")
    }

    private static func scenario_modelSave(_ ctx: ModelContext) throws {
        let p = Project(title: "Save Test", logline: "")
        ctx.insert(p)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<Project>())
        try assert(fetched.contains { $0.id == p.id }, "saved project lost on fetch")
    }

    // MARK: - Helpers

    private static func assert(_ condition: Bool, _ detail: String) throws {
        if !condition { throw Failure(scenario: "assert", detail: detail) }
    }
}
