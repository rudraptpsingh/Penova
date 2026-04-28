//
//  PDFRoundTripImportTests.swift
//  PenovaTests
//
//  End-to-end "real" test for screenplay PDF onboarding. We build a
//  tiny SwiftData Project in memory, render it to PDF using the
//  app's ScriptPDFRenderer (real Courier 12pt, real WGA indents,
//  real PDFKit pipeline), then parse that PDF back through
//  PDFKitLineSource + PDFScreenplayParser and assert that the
//  scene/element structure round-trips with high fidelity.
//
//  This is the gold-standard regression test: synthetic mocks can
//  miss PDFKit-specific quirks (line ordering, character bounds
//  reporting, ligatures, page breaks). This test exercises the
//  actual code path the user hits when they pick a PDF.
//
//  Plus a fixture-loader that auto-runs against any *.pdf the user
//  drops into PenovaTests/Fixtures/screenplays/, so real-world
//  scripts get covered the moment they're added without code edits.
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
private func makeProject(in ctx: ModelContext) -> Project {
    let p = Project(title: "The Last Train")
    p.contactBlock = "penova@example.com\n+91 99999 99999"
    ctx.insert(p)
    let ep = Episode(title: "Pilot", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)

    let s1 = ScriptScene(locationName: "Mumbai Local Train", location: .interior, time: .night, order: 0)
    s1.episode = ep; ep.scenes.append(s1); ctx.insert(s1)
    addElements(to: s1, ctx: ctx, [
        (.heading, "INT. MUMBAI LOCAL TRAIN - NIGHT"),
        (.action, "Rain hammers the metal roof. IQBAL (mid-40s) clutches a thermos."),
        (.character, "IQBAL"),
        (.parenthetical, "(to himself)"),
        (.dialogue, "Not late. Not yet."),
        (.character, "RAVI"),
        (.dialogue, "Iqbal, step back from the edge."),
        (.transition, "CUT TO:"),
    ])

    let s2 = ScriptScene(locationName: "Signal Control Room", location: .interior, time: .continuous, order: 1)
    s2.episode = ep; ep.scenes.append(s2); ctx.insert(s2)
    addElements(to: s2, ctx: ctx, [
        (.heading, "INT. SIGNAL CONTROL ROOM - CONTINUOUS"),
        (.action, "Fluorescent light. RAVI flicks between two monitors."),
        (.character, "RAVI"),
        (.dialogue, "Whose shift was it the last time this happened?"),
        (.character, "MEENA"),
        (.parenthetical, "(quietly)"),
        (.dialogue, "The last time what happened?"),
        (.transition, "FADE OUT."),
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

@MainActor
@Suite struct PDFRoundTripImportTests {

    @Test func renderSeedThenParseRecoversAllScenesAndKinds() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        try ctx.save()

        let pdfURL = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        guard let pdfDoc = PDFDocument(url: pdfURL) else {
            #expect(Bool(false), "rendered PDF could not be opened by PDFKit")
            return
        }
        #expect(pdfDoc.pageCount >= 1)

        let source = PDFKitLineSource(document: pdfDoc)
        let result = PDFScreenplayParser.parse(source)

        // We don't require pixel-perfect fidelity; we require structural
        // fidelity: scene count + presence of every element kind we put in.
        #expect(result.document.scenes.count == 2,
                "expected 2 scenes, got \(result.document.scenes.count)")

        let allKinds = Set(result.document.scenes.flatMap { $0.elements.map(\.kind) })
        for required: SceneElementKind in [.character, .dialogue, .parenthetical, .transition, .action] {
            #expect(allKinds.contains(required),
                    "missing kind \(required) in round-trip — got \(allKinds)")
        }

        // Heading text round-trips.
        let headings = result.document.scenes.map { $0.heading.uppercased() }
        #expect(headings.contains(where: { $0.contains("MUMBAI LOCAL TRAIN") }))
        #expect(headings.contains(where: { $0.contains("SIGNAL CONTROL ROOM") }))

        // Character cues are clean — no parenthetical noise.
        let cues = result.document.scenes
            .flatMap { $0.elements.filter { $0.kind == .character } }
            .map(\.text)
        for c in cues {
            #expect(!c.contains("("), "cue still has paren suffix: \(c)")
        }
        #expect(Set(cues).isSuperset(of: ["IQBAL", "RAVI", "MEENA"]))

        // Title page: ScriptPDFRenderer emits one when the project has
        // a title, so the parser should surface a non-empty titlePage.
        #expect(result.diagnostics.hadTitlePage,
                "expected a title page on the rendered PDF")
        let titleField = result.document.titlePage["title"]
            ?? result.document.titlePage["Title"]
        #expect(titleField?.uppercased().contains("LAST TRAIN") == true,
                "title page didn't include the project title; got \(result.document.titlePage)")
    }

    @Test func importerLiftsRoundTrippedPDFIntoSwiftData() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let original = makeProject(in: ctx)
        try ctx.save()

        let pdfURL = try ScriptPDFRenderer.render(project: original)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let result = try ScreenplayImporter.importFile(at: pdfURL, into: ctx)

        // Importer creates a new project; original survives unchanged.
        let allProjects = try ctx.fetch(FetchDescriptor<Project>())
        #expect(allProjects.count == 2)

        let imported = result.project
        #expect(imported.episodes.count >= 1)
        let scenes = imported.episodes.first?.scenesOrdered ?? []
        #expect(scenes.count == 2)

        let elementKinds = Set(scenes.flatMap { $0.elements.map(\.kind) })
        for required: SceneElementKind in [.character, .dialogue, .parenthetical, .action] {
            #expect(elementKinds.contains(required))
        }
    }

    // MARK: - Fixture loader

    /// Auto-discovers any *.pdf in PenovaTests/Fixtures/screenplays/ and
    /// runs invariant assertions against each. To add a real public
    /// script: drop the PDF into that directory and re-run the suite —
    /// no code edits needed.
    @Test func realFixturesParseCleanly() throws {
        let urls = fixtureURLs(extension: "pdf")
        if urls.isEmpty {
            // No fixtures present: this is a no-op pass on CI boxes
            // without scripts. Real coverage runs on dev machines.
            return
        }
        for url in urls {
            guard let pdf = PDFDocument(url: url) else {
                #expect(Bool(false), "could not open fixture \(url.lastPathComponent)")
                continue
            }
            let result = PDFScreenplayParser.parse(PDFKitLineSource(document: pdf))
            // Permissive baseline — any well-formed screenplay must
            // yield at least one scene and at least one character cue.
            #expect(result.document.scenes.count >= 1,
                    "\(url.lastPathComponent): zero scenes parsed")
            let cueCount = result.document.scenes
                .flatMap { $0.elements.filter { $0.kind == .character } }.count
            #expect(cueCount >= 1,
                    "\(url.lastPathComponent): zero character cues — heuristic regressed")
        }
    }

    @Test func realFDXFixturesParseCleanly() throws {
        let urls = fixtureURLs(extension: "fdx")
        if urls.isEmpty { return }
        for url in urls {
            let data = try Data(contentsOf: url)
            let doc = try FDXReader.parse(data)
            #expect(doc.scenes.count >= 1, "\(url.lastPathComponent): zero scenes")
        }
    }

    // MARK: - Helpers

    private func fixtureURLs(extension ext: String) -> [URL] {
        let candidates = [
            // Test bundle resource path (works if fixtures are added to
            // the PenovaTests target).
            Bundle(for: TestBundleAnchor.self).resourceURL?
                .appendingPathComponent("Fixtures/screenplays"),
            // Source-tree path (works when running tests with CWD at
            // the project root, e.g. xcodebuild test from the repo).
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("PenovaTests/Fixtures/screenplays")
        ].compactMap { $0 }

        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir.path) {
                let urls = (try? FileManager.default
                    .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                let filtered = urls.filter {
                    $0.pathExtension.lowercased() == ext.lowercased()
                }
                if !filtered.isEmpty { return filtered }
            }
        }
        return []
    }
}

/// Anchor class used solely to find this test bundle's resource URL.
private final class TestBundleAnchor {}
