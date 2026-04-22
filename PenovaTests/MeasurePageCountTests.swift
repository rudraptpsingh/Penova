//
//  MeasurePageCountTests.swift
//  PenovaTests
//
//  Extra coverage for ScriptPDFRenderer.measurePageCount(project:).
//  Verifies layout-measure agrees with actually-rendered PDF across a
//  range of project shapes, and documents the caching behaviour
//  (there is none: it recomputes on every call).
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
@testable import Penova

@MainActor
@Suite struct MeasurePageCountTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    /// Count PDF pages in the rendered file via CGPDFDocument.
    private func renderedPageCount(_ project: Project) throws -> Int {
        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        let cf = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                               url.path as CFString,
                                               .cfurlposixPathStyle, false)
        guard let cf, let doc = CGPDFDocument(cf) else {
            Issue.record("could not open rendered PDF"); return 0
        }
        return doc.numberOfPages
    }

    @discardableResult
    private func addScene(
        _ ep: Episode,
        ctx: ModelContext,
        name: String,
        order: Int,
        body: [(SceneElementKind, String)] = [(.action, "A beat.")]
    ) -> ScriptScene {
        let s = ScriptScene(locationName: name, location: .interior, time: .day, order: order)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let h = SceneElement(kind: .heading, text: s.heading, order: 0)
        h.scene = s; s.elements.append(h); ctx.insert(h)
        for (i, pair) in body.enumerated() {
            let e = SceneElement(kind: pair.0, text: pair.1, order: i + 1)
            e.scene = s; s.elements.append(e); ctx.insert(e)
        }
        return s
    }

    // MARK: - Simple cases

    @Test func emptyProjectZeroPages() throws {
        let container = try makeContainer()
        let p = Project(title: "Empty")
        container.mainContext.insert(p); try container.mainContext.save()
        #expect(ScriptPDFRenderer.measurePageCount(project: p) == 0)
    }

    @Test func oneShortSceneOnePage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "One")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        addScene(ep, ctx: ctx, name: "Kitchen", order: 0)
        try ctx.save()
        #expect(ScriptPDFRenderer.measurePageCount(project: p) == 1)
    }

    // MARK: - Agreement with actually-rendered PDF across 5 shapes

    @Test func measureMatchesRenderedOneSceneProject() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "1-scene")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        addScene(ep, ctx: ctx, name: "Room", order: 0)
        try ctx.save()

        let measured = ScriptPDFRenderer.measurePageCount(project: p)
        let rendered = try renderedPageCount(p)
        #expect(rendered == measured + 1, "rendered=\(rendered) measured=\(measured)")
    }

    @Test func measureMatchesRenderedTenSceneProject() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "10-scene")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<10 {
            addScene(ep, ctx: ctx, name: "Loc \(i)", order: i,
                     body: [(.action, String(repeating: "Characters move. ", count: 6))])
        }
        try ctx.save()
        let measured = ScriptPDFRenderer.measurePageCount(project: p)
        let rendered = try renderedPageCount(p)
        #expect(rendered == measured + 1, "rendered=\(rendered) measured=\(measured)")
    }

    @Test func measureMatchesRenderedFiftySceneProject() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "50-scene")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<50 {
            addScene(ep, ctx: ctx, name: "Loc \(i)", order: i,
                     body: [(.action, "Short action \(i).")])
        }
        try ctx.save()
        let measured = ScriptPDFRenderer.measurePageCount(project: p)
        let rendered = try renderedPageCount(p)
        #expect(rendered == measured + 1, "rendered=\(rendered) measured=\(measured)")
    }

    @Test func measureMatchesRenderedMultiEpisode() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Multi-ep")
        ctx.insert(p)
        for e in 0..<3 {
            let ep = Episode(title: "Ep \(e + 1)", order: e)
            ep.project = p; p.episodes.append(ep); ctx.insert(ep)
            for i in 0..<5 {
                addScene(ep, ctx: ctx, name: "Loc \(e)-\(i)", order: i)
            }
        }
        try ctx.save()
        let measured = ScriptPDFRenderer.measurePageCount(project: p)
        let rendered = try renderedPageCount(p)
        #expect(rendered == measured + 1, "rendered=\(rendered) measured=\(measured)")
    }

    @Test func measureMatchesRenderedDialogueHeavy() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Dialogue heavy")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<8 {
            addScene(ep, ctx: ctx, name: "Convo \(i)", order: i, body: [
                (.action, "They sit."),
                (.character, "JANE"),
                (.dialogue, String(repeating: "Words happen across a long speech. ", count: 10)),
                (.character, "MARCUS"),
                (.parenthetical, "(beat)"),
                (.dialogue, String(repeating: "Longer reply that will wrap multiple times. ", count: 8))
            ])
        }
        try ctx.save()
        let measured = ScriptPDFRenderer.measurePageCount(project: p)
        let rendered = try renderedPageCount(p)
        #expect(rendered == measured + 1, "rendered=\(rendered) measured=\(measured)")
    }

    // MARK: - Caching behaviour — documented: none

    @Test func measurePageCountRecomputesAfterEdit() throws {
        // measurePageCount has no cache; mutating the project and calling
        // again must reflect the change. If a cache is ever added, it
        // MUST invalidate on updatedAt changes. Lock in the current
        // no-cache behaviour.
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Cache")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        addScene(ep, ctx: ctx, name: "Start", order: 0)
        try ctx.save()
        let before = ScriptPDFRenderer.measurePageCount(project: p)

        // Add many long action lines to push past one page.
        let s = ep.scenesOrdered[0]
        for i in 1...60 {
            let a = SceneElement(kind: .action,
                                 text: String(repeating: "Filler line to push the page. ", count: 4),
                                 order: 10 + i)
            a.scene = s; s.elements.append(a); ctx.insert(a)
        }
        s.updatedAt = .now
        try ctx.save()
        let after = ScriptPDFRenderer.measurePageCount(project: p)

        #expect(after > before, "page count should grow after content added: before=\(before) after=\(after)")
    }
}
