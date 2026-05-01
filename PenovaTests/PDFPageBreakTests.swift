//
//  PDFPageBreakTests.swift
//  PenovaTests
//
//  Pagination behaviour verified against ScriptPDFRenderer:
//    - Overflowing dialogue emits "(MORE)" at the parenthetical column on
//      the breaking page and "CHARACTER (CONT'D)" at the character column
//      on the next page.
//    - Dialogue column stays inside x=180..432.
//    - An actBreak element is rendered centered, uppercased, underlined
//      across the action column (midpoint ≈ 324). It does NOT force a new
//      page on its own unless the remaining vertical space is too small.
//    - Scene numbers run monotonically 1..N in a single-episode project.
//    - measurePageCount agrees with the actually rendered page count across
//      small, medium, and multi-episode projects.
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
import PDFKit
@testable import PenovaKit
@testable import Penova

@MainActor
@Suite struct PDFPageBreakTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    // MARK: - MORE / CONT'D

    @Test func longDialogueSplitsWithMoreAndContinued() throws {
        // Build a scene with one dialogue so long it must break across pages.
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "MoreContd")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "Cell", location: .interior, time: .night, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let h = SceneElement(kind: .heading, text: s.heading, order: 0)
        let c = SceneElement(kind: .character, text: "JANE", order: 1)
        // ~80 repetitions of a long phrase → >>1 page of dialogue.
        let words = String(repeating: "Speaking and speaking across the long night ", count: 80)
        let d = SceneElement(kind: .dialogue, text: words, order: 2, characterName: "JANE")
        for el in [h, c, d] { el.scene = s; s.elements.append(el); ctx.insert(el) }
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else { Issue.record("no doc"); return }
        #expect(doc.pageCount >= 3, "expected ≥3 pages (title + ≥2 script); got \(doc.pageCount)")

        // (MORE) must land on a script page and at the parenthetical column.
        let moreSels = doc.findString("(MORE)", withOptions: .literal)
        #expect(!moreSels.isEmpty, "(MORE) not emitted")
        for sel in moreSels {
            for page in sel.pages {
                if doc.index(for: page) == 0 { continue }
                let r = sel.bounds(for: page)
                #expect(abs(r.minX - 224) <= 4,
                        "(MORE) x=\(r.minX) expected at parenthetical column 224")
            }
        }

        // "JANE (CONT'D)" must land on a later script page than (MORE).
        let contdSels = doc.findString("JANE (CONT'D)", withOptions: .literal)
        #expect(!contdSels.isEmpty, "CHARACTER (CONT'D) not emitted")
        if let moreFirstPage = moreSels.first?.pages.first,
           let contdFirstPage = contdSels.first?.pages.first {
            #expect(doc.index(for: contdFirstPage) > doc.index(for: moreFirstPage),
                    "(CONT'D) page \(doc.index(for: contdFirstPage)) not after (MORE) page \(doc.index(for: moreFirstPage))")
            // (CONT'D) sits at the character cue column.
            let r = contdSels.first!.bounds(for: contdFirstPage)
            #expect(abs(r.minX - 266) <= 4, "(CONT'D) x=\(r.minX), expected 266")
        }
    }

    // MARK: - Dialogue column discipline

    @Test func dialogueStaysInsideDialogueColumn() throws {
        // Dialogue column: x ∈ [180, 432]. Every rendered wrap-line of a
        // dialogue block must sit inside that column.
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "DWrap")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "Room", location: .interior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let h = SceneElement(kind: .heading, text: s.heading, order: 0)
        let c = SceneElement(kind: .character, text: "ZZZZ", order: 1)
        // Use a unique token we can search across every wrapped line.
        let text = String(repeating: "DWRAPTOKEN meaningful speech across lines ", count: 6)
        let d = SceneElement(kind: .dialogue, text: text, order: 2, characterName: "ZZZZ")
        for el in [h, c, d] { el.scene = s; s.elements.append(el); ctx.insert(el) }
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else { Issue.record("no doc"); return }
        let sels = doc.findString("DWRAPTOKEN", withOptions: .literal)
        #expect(sels.count >= 2, "expected multiple wrapped lines; got \(sels.count)")
        for sel in sels {
            for page in sel.pages {
                if doc.index(for: page) == 0 { continue }
                let r = sel.bounds(for: page)
                #expect(r.minX >= 178, "dialogue token left=\(r.minX) before column")
                #expect(r.maxX <= 434, "dialogue token right=\(r.maxX) past column")
            }
        }
    }

    // MARK: - Act break

    @Test func actBreakIsCenteredAndUppercased() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Act")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "Stage", location: .interior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let h = SceneElement(kind: .heading, text: s.heading, order: 0)
        let a = SceneElement(kind: .action, text: "Silence.", order: 1)
        let ab = SceneElement(kind: .actBreak, text: "End of Act One", order: 2)
        for el in [h, a, ab] { el.scene = s; s.elements.append(el); ctx.insert(el) }
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else { Issue.record("no doc"); return }
        guard let sel = doc.findString("END OF ACT ONE", withOptions: .literal).first,
              let page = sel.pages.first else {
            Issue.record("uppercase act break not found"); return
        }
        #expect(doc.index(for: page) >= 1, "act break on title page?")
        let r = sel.bounds(for: page)
        // Centered inside the action box (x=108 width=432) → midpoint ≈ 324.
        let mid = (r.minX + r.maxX) / 2
        #expect(abs(mid - 324) <= 4, "act break midpoint=\(mid), expected ≈324")
        // And the lowercase source form is NOT emitted.
        #expect(doc.findString("End of Act One", withOptions: .literal).isEmpty)
    }

    // MARK: - Scene number monotonicity

    @Test func sceneNumbersAreMonotonicInSingleEpisode() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Mono")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<5 {
            let s = ScriptScene(locationName: "Loc \(i)", location: .interior, time: .day, order: i)
            s.episode = ep; ep.scenes.append(s); ctx.insert(s)
            let h = SceneElement(kind: .heading, text: s.heading, order: 0)
            let a = SceneElement(kind: .action, text: "Go.", order: 1)
            for el in [h, a] { el.scene = s; s.elements.append(el); ctx.insert(el) }
        }
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else { Issue.record("no doc"); return }

        // Each N in 1...5 must appear at the left gutter (x≈36).
        for n in 1...5 {
            let sels = doc.findString("\(n).", withOptions: .literal)
            let atLeftGutter = sels.contains { sel in
                sel.pages.contains { page in
                    guard doc.index(for: page) != 0 else { return false }
                    let r = sel.bounds(for: page)
                    return abs(r.minX - 36) <= 6
                }
            }
            #expect(atLeftGutter, "scene \(n) not at left gutter")
        }
        // Scene 6 does NOT appear.
        let sixSels = doc.findString("6.", withOptions: .literal)
        let sixAtGutter = sixSels.contains { sel in
            sel.pages.contains { page in
                guard doc.index(for: page) != 0 else { return false }
                let r = sel.bounds(for: page)
                return abs(r.minX - 36) <= 6
            }
        }
        #expect(!sixAtGutter, "scene 6 gutter marker unexpectedly present")
    }

    // MARK: - Measure equals render across sizes

    @Test func measureAgreesWithRenderAcrossThreeSizes() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Small: 1 short scene.
        let small = Project(title: "small")
        ctx.insert(small)
        let sep = Episode(title: "Ep", order: 0)
        sep.project = small; small.episodes.append(sep); ctx.insert(sep)
        let ssc = ScriptScene(locationName: "A", location: .interior, time: .day, order: 0)
        ssc.episode = sep; sep.scenes.append(ssc); ctx.insert(ssc)
        let sh = SceneElement(kind: .heading, text: ssc.heading, order: 0); sh.scene = ssc; ssc.elements.append(sh); ctx.insert(sh)
        let sa = SceneElement(kind: .action, text: "Hi.", order: 1); sa.scene = ssc; ssc.elements.append(sa); ctx.insert(sa)

        // Medium: enough content to force a page break.
        let medium = Project(title: "medium")
        ctx.insert(medium)
        let mep = Episode(title: "Ep", order: 0)
        mep.project = medium; medium.episodes.append(mep); ctx.insert(mep)
        for i in 0..<8 {
            let s = ScriptScene(locationName: "Loc \(i)", location: .interior, time: .day, order: i)
            s.episode = mep; mep.scenes.append(s); ctx.insert(s)
            let h = SceneElement(kind: .heading, text: s.heading, order: 0)
            h.scene = s; s.elements.append(h); ctx.insert(h)
            for k in 0..<8 {
                let a = SceneElement(kind: .action,
                                     text: "Characters move and something happens \(k).",
                                     order: k + 1)
                a.scene = s; s.elements.append(a); ctx.insert(a)
            }
        }

        // Large: multi-episode.
        let large = Project(title: "large")
        ctx.insert(large)
        for e in 0..<2 {
            let ep = Episode(title: "Ep \(e)", order: e)
            ep.project = large; large.episodes.append(ep); ctx.insert(ep)
            for i in 0..<15 {
                let s = ScriptScene(locationName: "L\(e)-\(i)",
                                    location: .interior, time: .day, order: i)
                s.episode = ep; ep.scenes.append(s); ctx.insert(s)
                let h = SceneElement(kind: .heading, text: s.heading, order: 0)
                h.scene = s; s.elements.append(h); ctx.insert(h)
                for k in 0..<4 {
                    let a = SceneElement(kind: .action, text: "Moment \(k).", order: k + 1)
                    a.scene = s; s.elements.append(a); ctx.insert(a)
                }
            }
        }

        try ctx.save()

        for project in [small, medium, large] {
            let measured = ScriptPDFRenderer.measurePageCount(project: project)
            let url = try ScriptPDFRenderer.render(project: project)
            defer { try? FileManager.default.removeItem(at: url) }
            guard let doc = PDFDocument(url: url) else {
                Issue.record("render failed for \(project.title)"); continue
            }
            #expect(doc.pageCount == measured + 1,
                    "\(project.title): measure=\(measured) rendered=\(doc.pageCount)")
        }
    }
}
