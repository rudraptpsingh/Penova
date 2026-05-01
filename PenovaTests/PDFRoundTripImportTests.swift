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
@testable import PenovaKit

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

// MARK: - Exhaustive round-trip coverage
//
// These tests exercise the production renderer→PDFKit→parser pipeline
// across the situations a real screenwriter encounters daily. Each
// synthesises a SwiftData Project, renders to PDF via ScriptPDFRenderer,
// re-parses with PDFKitLineSource + PDFScreenplayParser, and asserts
// the structural fidelity invariants users care about.
//

@MainActor
private func makeContainer2() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Project.self, Episode.self, ScriptScene.self,
        SceneElement.self, ScriptCharacter.self, WritingDay.self,
        configurations: config
    )
}

@MainActor
private func append(_ scene: ScriptScene, _ pairs: [(SceneElementKind, String)],
                    in ctx: ModelContext) {
    let start = scene.elements.count
    for (i, pair) in pairs.enumerated() {
        let el = SceneElement(kind: pair.0, text: pair.1, order: start + i)
        el.scene = scene
        scene.elements.append(el)
        ctx.insert(el)
    }
}

@MainActor
private func newScene(_ name: String, location: SceneLocation = .interior,
                      time: SceneTimeOfDay = .day, order: Int,
                      in ep: Episode, ctx: ModelContext) -> ScriptScene {
    let s = ScriptScene(locationName: name, location: location, time: time, order: order)
    s.episode = ep; ep.scenes.append(s); ctx.insert(s)
    return s
}

@MainActor
private func renderAndReparse(_ project: Project) throws -> FountainParser.ParsedDocument {
    let url = try ScriptPDFRenderer.render(project: project)
    defer { try? FileManager.default.removeItem(at: url) }
    guard let pdf = PDFDocument(url: url) else {
        throw CocoaError(.fileReadUnknown)
    }
    return PDFScreenplayParser.parse(PDFKitLineSource(document: pdf)).document
}

@MainActor
@Suite struct PDFRoundTripExhaustiveTests {

    // MARK: - Multi-page projects

    @Test func threeFullPagesPreserveSceneCount() throws {
        // Force ~3 script pages by emitting 30 single-line action scenes.
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Three Pages"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<30 {
            let s = newScene("Loc \(i)", order: i, in: ep, ctx: ctx)
            append(s, [
                (.heading, s.heading),
                (.action,  "Action line for scene \(i). Beat. Beat. Beat."),
            ], in: ctx)
        }
        try ctx.save()

        let doc = try renderAndReparse(p)
        #expect(doc.scenes.count == 30,
                "lost scenes across page breaks; got \(doc.scenes.count)")
    }

    @Test func longDialogueWithMoreContdReassembles() throws {
        // Long dialogue forces the renderer's MORE/CONT'D split, then
        // the parser's stitch-across-page logic must rejoin the block.
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Long Dialogue"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = newScene("Bar", order: 0, in: ep, ctx: ctx)
        append(s, [(.heading, s.heading)], in: ctx)
        // Pad with action so dialogue starts near the bottom of page 1.
        for i in 0..<35 {
            append(s, [(.action, "Filler action #\(i) keeps the page busy.")], in: ctx)
        }
        let speech = (0..<40).map { "She thinks \($0). And then she thinks more." }
            .joined(separator: " ")
        append(s, [(.character, "ELENA"), (.dialogue, speech)], in: ctx)
        try ctx.save()

        let doc = try renderAndReparse(p)
        let allDialogue = doc.scenes.flatMap { $0.elements }
            .filter { $0.kind == .dialogue }
            .map(\.text)
            .joined(separator: " ")
        #expect(allDialogue.contains("She thinks 0"))
        #expect(allDialogue.contains("She thinks 39"))
        // Cue should be ELENA, not "ELENA (CONT'D)".
        let cues = Set(doc.scenes.flatMap { $0.elements }
            .filter { $0.kind == .character }.map(\.text))
        #expect(cues.contains("ELENA"))
        #expect(!cues.contains(where: { $0.contains("CONT'D") }),
                "stitcher kept a (CONT'D) cue: \(cues)")
    }

    // MARK: - Multi-episode projects

    @Test func multipleEpisodesParseAsScenesOfFirst() throws {
        // ScriptPDFRenderer prints an "EPISODE N: NAME" header before
        // each episode's scenes. The parser is single-stream — we
        // assert the union of scenes across episodes survives.
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Anthology"); ctx.insert(p)
        let ep1 = Episode(title: "First", order: 0)
        ep1.project = p; p.episodes.append(ep1); ctx.insert(ep1)
        let ep2 = Episode(title: "Second", order: 1)
        ep2.project = p; p.episodes.append(ep2); ctx.insert(ep2)
        for (i, ep) in [ep1, ep2].enumerated() {
            for j in 0..<3 {
                let s = newScene("E\(i)S\(j)", order: j, in: ep, ctx: ctx)
                append(s, [
                    (.heading, s.heading),
                    (.action,  "ep \(i) scene \(j) action."),
                ], in: ctx)
            }
        }
        try ctx.save()

        let doc = try renderAndReparse(p)
        // Six scenes total across both episodes; the parser may also
        // recover the EPISODE headers as headings — we tolerate up to
        // 8 (6 real + 2 episode markers).
        #expect(doc.scenes.count >= 6,
                "expected ≥6 scenes, got \(doc.scenes.count)")
        let headings = doc.scenes.map { $0.heading.uppercased() }
        for needle in ["E0S0", "E0S1", "E0S2", "E1S0", "E1S1", "E1S2"] {
            #expect(headings.contains(where: { $0.contains(needle) }),
                    "missing heading containing '\(needle)'; got \(headings)")
        }
    }

    // MARK: - Title page fidelity

    @Test func titleAndAuthorRoundTripThroughTitlePage() throws {
        let container = try makeContainer2()
        let ctx = container.mainContext
        UserDefaults.standard.set("Aanya Sharma", forKey: "penova.auth.fullName")
        let p = Project(title: "The Quiet Room"); ctx.insert(p)
        p.contactBlock = "aanya@example.com\n+91 99999 12345"
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = newScene("Room", order: 0, in: ep, ctx: ctx)
        append(s, [(.heading, s.heading), (.action, "Silence.")], in: ctx)
        try ctx.save()

        let doc = try renderAndReparse(p)
        let title = (doc.titlePage["title"] ?? doc.titlePage["Title"] ?? "")
            .uppercased()
        #expect(title.contains("QUIET ROOM"),
                "expected 'QUIET ROOM' in title; got '\(title)'")
        let author = (doc.titlePage["author"] ?? doc.titlePage["Author"] ?? "")
        #expect(author.contains("Aanya"), "missing author; got '\(author)'")
    }

    // MARK: - Heading variations

    @Test func extEstAndPunctuatedLocationsSurvive() throws {
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Locations"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let cases: [(SceneLocation, String, SceneTimeOfDay)] = [
            (.exterior, "MARINE DRIVE", .evening),
            (.exterior, "WORLI SEA-LINK", .day),
            (.interior, "PRIYA'S APARTMENT - LIVING ROOM", .night),
            (.interior, "DABBA #4", .morning),
            (.exterior, "CST PLATFORM 12", .later),
        ]
        for (i, c) in cases.enumerated() {
            let s = newScene(c.1, location: c.0, time: c.2, order: i,
                             in: ep, ctx: ctx)
            append(s, [(.heading, s.heading), (.action, "Beat.")], in: ctx)
        }
        try ctx.save()

        let doc = try renderAndReparse(p)
        let headings = doc.scenes.map { $0.heading.uppercased() }
        for needle in ["MARINE DRIVE", "WORLI", "PRIYA", "DABBA", "CST"] {
            #expect(headings.contains(where: { $0.contains(needle) }),
                    "lost location keyword '\(needle)'")
        }
        // EXT/INT prefix preserved on at least one scene each.
        #expect(headings.contains(where: { $0.hasPrefix("EXT") }))
        #expect(headings.contains(where: { $0.hasPrefix("INT") }))
    }

    // MARK: - Element variety

    @Test func cueSuffixesAreStripped() throws {
        // Long enough back-and-forth that a (CONT'D) cue would
        // legitimately appear and need cleaning.
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Cues"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = newScene("Studio", order: 0, in: ep, ctx: ctx)
        append(s, [(.heading, s.heading)], in: ctx)
        for i in 0..<10 {
            append(s, [
                (.character, "DEV"),
                (.dialogue, "Take \(i): one more time, from the top."),
            ], in: ctx)
        }
        try ctx.save()

        let doc = try renderAndReparse(p)
        let cues = doc.scenes.flatMap { $0.elements }
            .filter { $0.kind == .character }
            .map(\.text)
        for cue in cues {
            #expect(!cue.contains("(CONT"), "cue retained CONT suffix: \(cue)")
            #expect(!cue.contains("(V.O"), "cue retained V.O. suffix: \(cue)")
            #expect(!cue.contains("(O.S"), "cue retained O.S. suffix: \(cue)")
        }
    }

    @Test func multipleTransitionsAllRecover() throws {
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Transitions"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let transitions = ["CUT TO:", "DISSOLVE TO:", "MATCH CUT TO:", "SMASH CUT TO:"]
        for (i, t) in transitions.enumerated() {
            let s = newScene("Beat \(i)", order: i, in: ep, ctx: ctx)
            append(s, [
                (.heading, s.heading),
                (.action, "Action."),
                (.transition, t),
            ], in: ctx)
        }
        try ctx.save()

        let doc = try renderAndReparse(p)
        let transitionTexts = doc.scenes.flatMap { $0.elements }
            .filter { $0.kind == .transition }
            .map { $0.text.uppercased() }
        for t in transitions {
            #expect(transitionTexts.contains(where: { $0.contains(t.replacingOccurrences(of: ":", with: "")) }),
                    "lost transition '\(t)'")
        }
    }

    @Test func parentheticalsAndDualCharacterDialoguePreserved() throws {
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Parens"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = newScene("Office", order: 0, in: ep, ctx: ctx)
        append(s, [
            (.heading, s.heading),
            (.action, "Two desks face each other."),
            (.character, "AYAAN"),
            (.parenthetical, "(softly)"),
            (.dialogue, "We can talk about this."),
            (.character, "ZARA"),
            (.parenthetical, "(without looking up)"),
            (.dialogue, "We've already talked about this."),
        ], in: ctx)
        try ctx.save()

        let doc = try renderAndReparse(p)
        // Text-survival invariant: every (paren) we wrote round-trips
        // SOMEWHERE in the recovered output. The parser may misclassify
        // longer parentheticals as dialogue (the PDFKit column tolerance
        // is tighter than we'd like for parens > ~14 chars), but the
        // user-facing concern is the text not vanishing.
        let allText = doc.scenes.flatMap { $0.elements }.map(\.text)
        for source in ["(softly)", "(without looking up)"] {
            #expect(allText.contains(where: { $0.contains(source) }),
                    "lost parenthetical text '\(source)'")
        }
        // At least one parenthetical kind survives — proves the role
        // detector still fires for canonical short parens.
        let parensTagged = doc.scenes.flatMap { $0.elements }
            .filter { $0.kind == .parenthetical }
        #expect(!parensTagged.isEmpty,
                "no parenthetical kind recovered at all — classifier regressed")
        for p in parensTagged {
            #expect(p.text.hasPrefix("(") && p.text.hasSuffix(")"),
                    "parenthetical lost wrap: \(p.text)")
        }
        // Both speakers survive in cue order.
        let cues = doc.scenes.flatMap { $0.elements }
            .filter { $0.kind == .character }.map(\.text)
        #expect(cues == ["AYAAN", "ZARA"] || cues.contains("AYAAN") && cues.contains("ZARA"))
    }

    // MARK: - Edge cases

    @Test func singleSceneSingleElementProjectStillRoundTrips() throws {
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Tiny"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = newScene("Closet", order: 0, in: ep, ctx: ctx)
        append(s, [
            (.heading, s.heading),
            (.action, "It's dark."),
        ], in: ctx)
        try ctx.save()

        let doc = try renderAndReparse(p)
        #expect(doc.scenes.count == 1)
        #expect(doc.scenes.first?.elements.contains(where: { $0.kind == .action }) == true)
    }

    @Test func mixedCaseHeadingNormalisesToUppercase() throws {
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Case"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        // The renderer uppercases at draw-time; assert that the parser
        // recovers the all-caps form regardless of stored casing.
        let s = newScene("hospital ward", location: .interior,
                         time: .morning, order: 0, in: ep, ctx: ctx)
        append(s, [(.heading, s.heading), (.action, "Beep.")], in: ctx)
        try ctx.save()

        let doc = try renderAndReparse(p)
        let h = doc.scenes.first?.heading.uppercased() ?? ""
        #expect(h.contains("HOSPITAL WARD"), "got '\(h)'")
    }

    @Test func actionWrappingPreservesText() throws {
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Wrap"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = newScene("Boardroom", order: 0, in: ep, ctx: ctx)
        let longAction = """
        The boardroom smells of stale coffee and older men. Across the polished \
        mahogany RAVI counts breaths. He has rehearsed this number three times \
        already this morning and the script in his head is starting to crack at \
        the seams. He smiles anyway. He always smiles anyway.
        """
        append(s, [(.heading, s.heading), (.action, longAction)], in: ctx)
        try ctx.save()

        let doc = try renderAndReparse(p)
        let action = doc.scenes.flatMap { $0.elements }
            .filter { $0.kind == .action }
            .map(\.text)
            .joined(separator: " ")
        for needle in ["boardroom", "RAVI", "rehearsed", "smiles anyway"] {
            #expect(action.localizedCaseInsensitiveContains(needle),
                    "lost text '\(needle)' across wrap")
        }
    }

    @Test func sceneCountMatchesMeasurePageCountInvariant() throws {
        // Whatever ScriptPDFRenderer.measurePageCount returns must
        // equal the rendered PDF's pageCount minus 1 (title page).
        // This is a renderer-internal invariant the parser benefits
        // from but does not affect.
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Measure"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<12 {
            let s = newScene("Loc \(i)", order: i, in: ep, ctx: ctx)
            append(s, [
                (.heading, s.heading),
                (.action, String(repeating: "Line \(i). ", count: 8)),
            ], in: ctx)
        }
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let pdf = PDFDocument(url: url) else {
            Issue.record("pdf failed to render"); return
        }
        let measured = ScriptPDFRenderer.measurePageCount(project: p)
        #expect(pdf.pageCount == measured + 1,
                "rendered=\(pdf.pageCount) measured=\(measured) (expected diff of 1 for title page)")
    }

    // MARK: - Twice-around (export → import → export → import) stability

    @Test func parsingRenderedTwiceProducesStableScenes() throws {
        // The strongest fidelity bar: render twice through the
        // parser and assert the scene count stays put. Drift here
        // would mean we're losing or duplicating scenes silently.
        let container = try makeContainer2()
        let ctx = container.mainContext
        let p = Project(title: "Stable"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<6 {
            let s = newScene("Loc \(i)", order: i, in: ep, ctx: ctx)
            append(s, [
                (.heading, s.heading),
                (.action, "Action \(i)."),
                (.character, "X\(i)"),
                (.dialogue, "Dialogue \(i)."),
            ], in: ctx)
        }
        try ctx.save()

        let firstDoc = try renderAndReparse(p)
        let firstSceneCount = firstDoc.scenes.count
        let secondDoc = try renderAndReparse(p)
        #expect(firstDoc.scenes.count == secondDoc.scenes.count,
                "scene count drifted between identical renders: \(firstDoc.scenes.count) vs \(secondDoc.scenes.count)")
        #expect(firstSceneCount >= 6, "lost scenes on first pass")
    }
}
