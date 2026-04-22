//
//  ScenePDFContentTests.swift
//  PenovaTests
//
//  Parses the rendered PDF text (via PDFKit) and asserts the scene-number
//  gutter markers and the title-page contact block survive into the output.
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
import PDFKit
@testable import Penova

@MainActor
@Suite struct ScenePDFContentTests {

    // MARK: helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    /// Insert a scene with heading + a short action line.
    @discardableResult
    private func addScene(
        to ep: Episode,
        ctx: ModelContext,
        location: SceneLocation = .interior,
        name: String,
        time: SceneTimeOfDay = .day,
        order: Int,
        actionText: String = "A beat."
    ) -> ScriptScene {
        let s = ScriptScene(locationName: name, location: location, time: time, order: order)
        s.episode = ep
        ep.scenes.append(s)
        ctx.insert(s)
        let h = SceneElement(kind: .heading, text: s.heading, order: 0)
        h.scene = s; s.elements.append(h); ctx.insert(h)
        let a = SceneElement(kind: .action, text: actionText, order: 1)
        a.scene = s; s.elements.append(a); ctx.insert(a)
        return s
    }

    /// Read full plain text out of the PDF at `url` via PDFKit.
    private func pdfText(at url: URL) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        var out = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string {
                out += s + "\n---PAGE---\n"
            }
        }
        return out
    }

    private func pdfTextPerPage(at url: URL) -> [String] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var out: [String] = []
        for i in 0..<doc.pageCount {
            out.append(doc.page(at: i)?.string ?? "")
        }
        return out
    }

    // MARK: - Scene-number gutter tests

    @Test func threeSceneProjectEmitsNumbers1Through3() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Gutters")
        ctx.insert(project)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        addScene(to: ep, ctx: ctx, name: "Alpha", order: 0)
        addScene(to: ep, ctx: ctx, name: "Bravo", order: 1)
        addScene(to: ep, ctx: ctx, name: "Charlie", order: 2)
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = pdfText(at: url)
        // Left + right gutter each render "N." next to each scene heading.
        #expect(text.contains("1."))
        #expect(text.contains("2."))
        #expect(text.contains("3."))
    }

    @Test func emptyProjectRendersWithoutSceneNumbersOrCrash() throws {
        let container = try makeContainer()
        let project = Project(title: "Empty")
        container.mainContext.insert(project)
        try container.mainContext.save()

        // Must not throw.
        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }

        // Title page only → no body to carry numbered gutter markers.
        // PDFKit can still read the file. measurePageCount is 0.
        let measured = ScriptPDFRenderer.measurePageCount(project: project)
        #expect(measured == 0)
    }

    @Test func sceneNumberAppearsTwicePerScene() throws {
        // Gutter markers render on both the left and right side of every
        // scene heading → each "N." substring should occur at least 2× in
        // the PDF text stream (one per gutter). We check across pages.
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Twice")
        ctx.insert(project)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let sceneCount = 2
        for i in 0..<sceneCount {
            addScene(to: ep, ctx: ctx, name: "Loc \(i)", order: i)
        }
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = pdfText(at: url)

        // "1." should show up ≥ 2 times (left + right gutter).
        // "2." likewise. We count occurrences of each label.
        for number in 1...sceneCount {
            let label = "\(number)."
            let occurrences = text.components(separatedBy: label).count - 1
            #expect(occurrences >= 2,
                    "expected ≥2 occurrences of '\(label)' (left+right gutter), got \(occurrences)")
        }
    }

    @Test func multiEpisodeResetsSceneNumberingPerEpisode() throws {
        // The implementation in ScriptPDFRenderer.layout() sets
        // `resetPerEpisode = project.activeEpisodesOrdered.count > 1`
        // and resets sceneNumber to 1 at the start of each episode.
        // This test locks in that semantic.
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Multi")
        ctx.insert(project)
        let ep1 = Episode(title: "One", order: 0)
        ep1.project = project; project.episodes.append(ep1); ctx.insert(ep1)
        addScene(to: ep1, ctx: ctx, name: "EpOneA", order: 0)
        addScene(to: ep1, ctx: ctx, name: "EpOneB", order: 1)
        let ep2 = Episode(title: "Two", order: 1)
        ep2.project = project; project.episodes.append(ep2); ctx.insert(ep2)
        addScene(to: ep2, ctx: ctx, name: "EpTwoA", order: 0)
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = pdfText(at: url)

        // Numbering resets: we never expect a "3." because episode 2 starts at 1.
        // "1." and "2." must exist; "3." must NOT.
        #expect(text.contains("1."))
        #expect(text.contains("2."))
        // This asserts the chosen "per-episode reset" semantic rather than global 1..N.
        #expect(!text.contains("3."))
    }

    // MARK: - Title page content tests

    @Test func titlePageOmitsMarketingLine() throws {
        let container = try makeContainer()
        let project = Project(title: "No Marketing")
        container.mainContext.insert(project)
        try container.mainContext.save()

        UserDefaults.standard.set("Jane Writer", forKey: "penova.auth.fullName")
        defer { UserDefaults.standard.removeObject(forKey: "penova.auth.fullName") }

        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }

        let pages = pdfTextPerPage(at: url)
        guard let title = pages.first else {
            Issue.record("no pages in PDF"); return
        }
        #expect(title.contains("Jane Writer"))
        // No hardcoded "Drafted in Penova" fallback.
        #expect(!title.localizedCaseInsensitiveContains("Drafted in Penova"))
    }

    @Test func contactBlockRendersBothLinesInPDF() throws {
        let container = try makeContainer()
        let project = Project(title: "With Contact")
        project.contactBlock = "me@x.com\n+1 555 0100"
        container.mainContext.insert(project)
        try container.mainContext.save()

        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = pdfTextPerPage(at: url)
        guard let title = pages.first else {
            Issue.record("no title page"); return
        }
        #expect(title.contains("me@x.com"))
        #expect(title.contains("555 0100"))
    }

    @Test func contactBlockWithSpecialCharactersDoesNotCrash() throws {
        let container = try makeContainer()
        let project = Project(title: "Special")
        project.contactBlock = "A & B <test>\n\"Bob\" O'Shea\nagent@x.com"
        container.mainContext.insert(project)
        try container.mainContext.save()

        // Must render without throwing and produce a readable PDF.
        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        #expect(data.count > 0)
        #expect(data.prefix(5) == Data("%PDF-".utf8))
    }

    @Test func missingAuthorAndEmptyContactRendersGracefully() throws {
        UserDefaults.standard.removeObject(forKey: "penova.auth.fullName")
        let container = try makeContainer()
        let project = Project(title: "Ghosted")
        container.mainContext.insert(project)
        try container.mainContext.save()

        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        #expect(data.count > 0)
        #expect(data.prefix(5) == Data("%PDF-".utf8))
    }
}
