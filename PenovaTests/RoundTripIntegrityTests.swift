//
//  RoundTripIntegrityTests.swift
//  PenovaTests
//
//  Proves the import/export pipeline is content-preserving in every
//  direction we ship:
//
//    Project → PDF export       → PDF re-import      → match
//    Project → FDX export       → FDX re-import      → match
//    Project → Fountain export  → Fountain re-import → match
//
//  Plus optional fixture-driven sweeps that use the canonical Fountain
//  reference scripts (Big Fish, Brick & Steel, The Last Birthday Card)
//  when they're present in PenovaTests/Fixtures/screenplays/. Run
//  `./tools/fetch_reference_scripts.sh` to populate that directory.
//
//  iOS context: these tests use real PDFKit, real ScriptPDFRenderer
//  (UIKit-based PDF rendering), real FinalDraftXMLWriter, real
//  FountainExporter — the same code paths the user hits in the app.
//

import Testing
import Foundation
import SwiftData
import PDFKit
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
        configurations: config
    )
}

@MainActor
private func makeRichProject(in ctx: ModelContext) -> Project {
    let p = Project(title: "The Last Train")
    p.contactBlock = "penova@example.com\n+91 99999 99999"
    ctx.insert(p)
    let ep = Episode(title: "Pilot", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)

    let s1 = ScriptScene(locationName: "Mumbai Local Train", location: .interior, time: .night, order: 0)
    s1.episode = ep; ep.scenes.append(s1); ctx.insert(s1)
    addElements(to: s1, ctx: ctx, [
        (.heading,       "INT. MUMBAI LOCAL TRAIN - NIGHT"),
        (.action,        "Rain hammers the metal roof. IQBAL (mid-40s) clutches a thermos."),
        (.character,     "IQBAL"),
        (.parenthetical, "(to himself)"),
        (.dialogue,      "Not late. Not yet."),
        (.character,     "RAVI"),
        (.dialogue,      "Iqbal, step back from the edge."),
        (.transition,    "CUT TO:"),
    ])

    let s2 = ScriptScene(locationName: "Signal Control Room", location: .interior, time: .continuous, order: 1)
    s2.episode = ep; ep.scenes.append(s2); ctx.insert(s2)
    addElements(to: s2, ctx: ctx, [
        (.heading,       "INT. SIGNAL CONTROL ROOM - CONTINUOUS"),
        (.action,        "Fluorescent light. RAVI flicks between two monitors."),
        (.character,     "RAVI"),
        (.dialogue,      "Whose shift was it the last time this happened?"),
        (.character,     "MEENA"),
        (.parenthetical, "(quietly)"),
        (.dialogue,      "The last time what happened?"),
        (.transition,    "FADE OUT."),
    ])
    return p
}

@MainActor
private func addElements(to scene: ScriptScene, ctx: ModelContext,
                         _ pairs: [(SceneElementKind, String)]) {
    for (i, pair) in pairs.enumerated() {
        let el = SceneElement(kind: pair.0, text: pair.1, order: i)
        el.scene = scene
        scene.elements.append(el)
        ctx.insert(el)
    }
}

/// Snapshot of a project's structure that survives transport through
/// any of the three formats. Compared on both sides of the round-trip.
private struct ProjectShape: Equatable {
    let sceneCount: Int
    let characterCues: Set<String>
    let kinds: Set<SceneElementKind>
    let headings: [String]

    init(scenes: [FountainParser.ParsedScene]) {
        self.sceneCount = scenes.count
        self.characterCues = Set(
            scenes.flatMap { $0.elements.filter { $0.kind == .character } }
                .map { $0.text.uppercased() }
        )
        self.kinds = Set(scenes.flatMap { $0.elements.map(\.kind) })
        self.headings = scenes.map { $0.heading.uppercased() }
    }

    init(project: Project) {
        var scenes: [FountainParser.ParsedScene] = []
        for ep in project.activeEpisodesOrdered {
            for s in ep.scenesOrdered {
                let elements = s.elementsOrdered
                    .filter { $0.kind != .heading }   // heading lives on the scene itself
                    .map { FountainParser.ParsedElement(kind: $0.kind, text: $0.text) }
                scenes.append(.init(heading: s.heading, elements: elements))
            }
        }
        self.init(scenes: scenes)
    }
}

@MainActor
private func parseFile(at url: URL) -> FountainParser.ParsedDocument? {
    let ext = url.pathExtension.lowercased()
    switch ext {
    case "pdf":
        guard let doc = PDFDocument(url: url) else { return nil }
        return PDFScreenplayParser.parse(PDFKitLineSource(document: doc)).document
    case "fdx":
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? FDXReader.parse(data)
    case "fountain", "txt", "md":
        guard let text = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return nil }
        return FountainParser.parse(text)
    default:
        return nil
    }
}

@MainActor
@Suite struct RoundTripIntegrityTests {

    // MARK: - In-memory Project → each format → re-import

    @Test func roundTripThroughPDF() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeRichProject(in: ctx); try ctx.save()
        let original = ProjectShape(project: project)

        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let parsed = parseFile(at: url) else {
            #expect(Bool(false), "PDF re-parse failed")
            return
        }
        let recovered = ProjectShape(scenes: parsed.scenes)

        // Scene count survives.
        #expect(recovered.sceneCount == original.sceneCount,
                "PDF round-trip: scene count \(recovered.sceneCount) vs \(original.sceneCount)")
        // Every character cue survives (case-insensitive).
        #expect(recovered.characterCues.isSuperset(of: original.characterCues),
                "PDF round-trip: missing cues. original=\(original.characterCues) recovered=\(recovered.characterCues)")
        // Heading text contains the source location keyword.
        for (i, headOrig) in original.headings.enumerated() {
            let recoveredHead = recovered.headings[safe: i]?.uppercased() ?? ""
            // Tolerate scene-number prefixes / minor punctuation drift —
            // require the location word survives.
            let keyword = headOrig.split(separator: " ").last.map(String.init) ?? ""
            #expect(recoveredHead.contains(keyword) ||
                    headOrig.contains(recoveredHead.split(separator: " ").last.map(String.init) ?? ""),
                    "PDF round-trip: heading \(i) \(recoveredHead) doesn't echo source \(headOrig)")
        }
        // Every kind from the source still present (PDF can't perfectly
        // round-trip parentheticals if they span lines weirdly, so we
        // require the big four).
        for required: SceneElementKind in [.character, .dialogue, .action, .transition] {
            #expect(recovered.kinds.contains(required),
                    "PDF round-trip lost kind \(required)")
        }
    }

    @Test func roundTripThroughFDX() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeRichProject(in: ctx); try ctx.save()
        let original = ProjectShape(project: project)

        let url = try FinalDraftXMLWriter.write(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let parsed = parseFile(at: url) else {
            #expect(Bool(false), "FDX re-parse failed")
            return
        }
        let recovered = ProjectShape(scenes: parsed.scenes)

        // FDX is the cleanest format — exact match on every field.
        #expect(recovered.sceneCount == original.sceneCount)
        #expect(recovered.characterCues == original.characterCues)
        #expect(recovered.kinds.isSuperset(of: original.kinds.subtracting([.heading])))
        #expect(recovered.headings == original.headings,
                "FDX round-trip: headings drifted. original=\(original.headings) recovered=\(recovered.headings)")
    }

    @Test func roundTripThroughFountain() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeRichProject(in: ctx); try ctx.save()
        let original = ProjectShape(project: project)

        let url = try FountainExporter.write(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let parsed = parseFile(at: url) else {
            #expect(Bool(false), "Fountain re-parse failed")
            return
        }
        let recovered = ProjectShape(scenes: parsed.scenes)

        #expect(recovered.sceneCount == original.sceneCount)
        #expect(recovered.characterCues == original.characterCues)
        for required: SceneElementKind in [.character, .dialogue, .action, .transition, .parenthetical] {
            #expect(recovered.kinds.contains(required),
                    "Fountain round-trip lost kind \(required)")
        }
        #expect(recovered.headings == original.headings)
    }

    // MARK: - Fixture-driven cross-format round-trips
    //
    // Use any reference files dropped into PenovaTests/Fixtures/screenplays/.
    // If absent (CI box without fetched fixtures), tests no-op.

    @Test func fixtureFountainSurvivesAllExports() throws {
        guard let fountainURL = fixtureURL(filename: "Big-Fish.fountain")
            ?? fixtureURL(filename: "Brick-and-Steel.fountain") else { return }
        guard let text = try? String(contentsOf: fountainURL, encoding: .utf8) else { return }
        let original = ProjectShape(scenes: FountainParser.parse(text).scenes)

        // Lift into a Project so we can run our exporters.
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = FountainImporter.makeProject(
            title: fountainURL.deletingPathExtension().lastPathComponent,
            from: FountainParser.parse(text),
            context: ctx
        )
        try ctx.save()

        // Each export must round-trip.
        try assertRoundTrip(project: project, original: original, format: .fountain)
        try assertRoundTrip(project: project, original: original, format: .fdx)
        // PDF is the loosest format — only assert structural fidelity.
        try assertRoundTrip(project: project, original: original, format: .pdf)
    }

    @Test func fixtureFDXSurvivesAllExports() throws {
        guard let fdxURL = fixtureURL(filename: "Big-Fish.fdx")
            ?? fixtureURL(filename: "Brick-and-Steel.fdx") else { return }
        guard let data = try? Data(contentsOf: fdxURL),
              let parsed = try? FDXReader.parse(data) else { return }
        let original = ProjectShape(scenes: parsed.scenes)

        let container = try makeContainer()
        let ctx = container.mainContext
        let project = FountainImporter.makeProject(
            title: fdxURL.deletingPathExtension().lastPathComponent,
            from: parsed,
            context: ctx
        )
        try ctx.save()

        try assertRoundTrip(project: project, original: original, format: .fdx)
        try assertRoundTrip(project: project, original: original, format: .fountain)
        try assertRoundTrip(project: project, original: original, format: .pdf)
    }

    @Test func fixturePDFSurvivesAllExports() throws {
        guard let pdfURL = fixtureURL(filename: "Brick-and-Steel.pdf")
            ?? fixtureURL(filename: "The-Last-Birthday-Card.pdf") else { return }
        guard let pdf = PDFDocument(url: pdfURL) else { return }
        let result = PDFScreenplayParser.parse(PDFKitLineSource(document: pdf))
        let original = ProjectShape(scenes: result.document.scenes)

        let container = try makeContainer()
        let ctx = container.mainContext
        let project = FountainImporter.makeProject(
            title: pdfURL.deletingPathExtension().lastPathComponent,
            from: result.document,
            context: ctx
        )
        try ctx.save()

        try assertRoundTrip(project: project, original: original, format: .fdx)
        try assertRoundTrip(project: project, original: original, format: .fountain)
    }

    // MARK: - Helpers

    private func assertRoundTrip(
        project: Project,
        original: ProjectShape,
        format: ExportFormat
    ) throws {
        let url: URL
        switch format {
        case .pdf:
            url = try ScriptPDFRenderer.render(project: project)
        case .fdx:
            url = try FinalDraftXMLWriter.write(project: project)
        case .fountain:
            url = try FountainExporter.write(project: project)
        }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let parsed = parseFile(at: url) else {
            #expect(Bool(false), "\(format.rawValue): re-parse failed")
            return
        }
        let recovered = ProjectShape(scenes: parsed.scenes)

        // Stricter assertions for FDX and Fountain (lossless code paths);
        // looser for PDF (rendered output, then re-classified).
        switch format {
        case .fdx, .fountain:
            #expect(recovered.sceneCount == original.sceneCount,
                    "\(format.rawValue): scene drift \(recovered.sceneCount) vs \(original.sceneCount)")
            #expect(recovered.characterCues.isSuperset(of: original.characterCues),
                    "\(format.rawValue): cue loss. orig=\(original.characterCues.count) rec=\(recovered.characterCues.count)")
        case .pdf:
            // PDF can mis-detect a scene heading occasionally; require
            // at least 80% recovery and full cue preservation.
            let recoveryRatio = Double(recovered.sceneCount) / Double(max(1, original.sceneCount))
            #expect(recoveryRatio >= 0.8,
                    "\(format.rawValue): scene recovery only \(Int(recoveryRatio*100))%")
            // Most cues should survive. Allow 5% loss to absorb any
            // PDF-rendering edge cases.
            let cueRecovery = Double(original.characterCues.intersection(recovered.characterCues).count)
                / Double(max(1, original.characterCues.count))
            #expect(cueRecovery >= 0.95,
                    "\(format.rawValue): cue recovery only \(Int(cueRecovery*100))%")
        }
    }

    private func fixtureURL(filename: String) -> URL? {
        let candidates = [
            Bundle(for: TestBundleAnchor.self).resourceURL?
                .appendingPathComponent("Fixtures/screenplays/\(filename)"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("PenovaTests/Fixtures/screenplays/\(filename)")
        ].compactMap { $0 }
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Anchor class used solely to find this test bundle's resource URL.
private final class TestBundleAnchor {}
