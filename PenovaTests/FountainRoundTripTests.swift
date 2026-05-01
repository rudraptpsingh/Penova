//
//  FountainRoundTripTests.swift
//  PenovaTests
//
//  Exercises Fountain export → parse round-trip, plus measurePageCount
//  helper. Keeps the bar pragmatic: we don't assert byte-for-byte file
//  equality, just that the structural skeleton survives the round-trip.
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
import PenovaKit
@testable import Penova

@MainActor
@Suite struct FountainRoundTripTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    private func seededProject(in ctx: ModelContext) -> Project {
        let project = Project(title: "Round Trip", logline: "Export, reimport, survive.")
        ctx.insert(project)

        let ep = Episode(title: "Pilot", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)

        // Scene 1: INT. COFFEE SHOP - DAY. Jane says something.
        let s1 = ScriptScene(locationName: "Coffee Shop", location: .interior, time: .day, order: 0)
        s1.episode = ep; ep.scenes.append(s1); ctx.insert(s1)
        for (kind, text, order) in [
            (SceneElementKind.heading, s1.heading, 0),
            (.action, "JANE enters, shaking off the rain.", 1),
            (.character, "JANE", 2),
            (.parenthetical, "(to the barista)", 3),
            (.dialogue, "Double espresso. Make it a triple.", 4)
        ] as [(SceneElementKind, String, Int)] {
            let el = SceneElement(kind: kind, text: text, order: order)
            el.scene = s1; s1.elements.append(el); ctx.insert(el)
        }

        // Scene 2: EXT. ROOFTOP - NIGHT.
        let s2 = ScriptScene(locationName: "Rooftop", location: .exterior, time: .night, order: 1)
        s2.episode = ep; ep.scenes.append(s2); ctx.insert(s2)
        for (kind, text, order) in [
            (SceneElementKind.heading, s2.heading, 0),
            (.action, "The city hums below. MARCUS lights a cigarette.", 1),
            (.character, "MARCUS", 2),
            (.dialogue, "She was right about the rain.", 3)
        ] as [(SceneElementKind, String, Int)] {
            let el = SceneElement(kind: kind, text: text, order: order)
            el.scene = s2; s2.elements.append(el); ctx.insert(el)
        }
        try? ctx.save()
        return project
    }

    @Test func fountainRoundTripPreservesScenesAndDialogue() throws {
        let container = try makeContainer()
        let project = seededProject(in: container.mainContext)

        let fountain = FountainExporter.export(project: project)
        let parsed = FountainParser.parse(fountain)

        #expect(parsed.scenes.count == 2)
        #expect(parsed.scenes[0].heading.contains("COFFEE SHOP"))
        #expect(parsed.scenes[1].heading.contains("ROOFTOP"))

        // Round-trip dialogue text.
        let allDialogue = parsed.scenes
            .flatMap { $0.elements }
            .filter { $0.kind == .dialogue }
            .map { $0.text }
        #expect(allDialogue.contains(where: { $0.contains("triple") }))
        #expect(allDialogue.contains(where: { $0.contains("rain") }))

        // Parenthetical preserved.
        let parens = parsed.scenes.flatMap { $0.elements }.filter { $0.kind == .parenthetical }
        #expect(parens.contains(where: { $0.text.contains("barista") }))
    }

    @Test func parserHandlesScrappyRealWorldSample() throws {
        // The kind of sloppy input a user might paste: mixed casing, missing
        // blank lines in places, stray whitespace, a title page on top.
        let sample = """
        Title: The Last Train
        Author: Rudra Singh

        INT. TRAIN CARRIAGE - NIGHT

        The lights flicker. NORA grips her bag.

        NORA
        (quietly)
        Not again.

        EXT. PLATFORM - CONTINUOUS

        Steam. The train stalls.

        CONDUCTOR
        All passengers please remain seated.

        CUT TO:

        INT. STATION - MORNING

        Empty benches.
        """

        let doc = FountainParser.parse(sample)
        #expect(doc.titlePage["title"] == "The Last Train")
        #expect(doc.scenes.count == 3)

        // Dialogue and parenthetical classified correctly.
        let firstScene = doc.scenes[0]
        #expect(firstScene.elements.contains(where: { $0.kind == .character && $0.text == "NORA" }))
        #expect(firstScene.elements.contains(where: { $0.kind == .parenthetical }))
        #expect(firstScene.elements.contains(where: { $0.kind == .dialogue && $0.text.contains("Not again") }))

        // Transition captured.
        let allKinds = doc.scenes.flatMap { $0.elements.map(\.kind) }
        #expect(allKinds.contains(.transition))
    }

    @Test func measurePageCountOnNonEmptyProject() throws {
        let container = try makeContainer()
        let project = seededProject(in: container.mainContext)
        let pages = ScriptPDFRenderer.measurePageCount(project: project)
        #expect(pages > 0)
    }

    @Test func measurePageCountOnEmptyProject() throws {
        let container = try makeContainer()
        let project = Project(title: "Empty")
        container.mainContext.insert(project)
        try container.mainContext.save()
        let pages = ScriptPDFRenderer.measurePageCount(project: project)
        #expect(pages == 0)
    }

    @Test func measurePageCountMatchesRenderedPDF() throws {
        // Layout math used for measurePageCount has to agree with what the
        // real renderer emits. Build a project big enough to span >1 page
        // and compare.
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Many Pages")
        ctx.insert(project)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        for i in 0..<25 {
            let s = ScriptScene(locationName: "Location \(i)", location: .interior, time: .day, order: i)
            s.episode = ep; ep.scenes.append(s); ctx.insert(s)
            let h = SceneElement(kind: .heading, text: s.heading, order: 0)
            h.scene = s; s.elements.append(h); ctx.insert(h)
            let a = SceneElement(kind: .action,
                                 text: String(repeating: "The character waits in the room. ", count: 8),
                                 order: 1)
            a.scene = s; s.elements.append(a); ctx.insert(a)
        }
        try ctx.save()

        let measured = ScriptPDFRenderer.measurePageCount(project: project)
        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }

        // Count "/Type /Page" occurrences (one per page including title page).
        let pdf = try Data(contentsOf: url)
        guard let pdfString = String(data: pdf, encoding: .isoLatin1) else {
            Issue.record("could not decode pdf"); return
        }
        // Count pages via CGPDFDocument for a reliable figure.
        let doc = CGPDFDocument(CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                              url.path as CFString,
                                                              .cfurlposixPathStyle, false))!
        let totalPages = doc.numberOfPages
        // Rendered PDF = title page + numbered script pages.
        // measurePageCount excludes the title page.
        #expect(totalPages == measured + 1, "\(totalPages) vs measured=\(measured); pdfString prefix: \(pdfString.prefix(40))")
    }
}
