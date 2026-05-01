//
//  PDFLayoutTests.swift
//  PenovaTests
//
//  Parses PDFs rendered by ScriptPDFRenderer with PDFKit and asserts the
//  physical layout matches industry screenplay conventions: page size,
//  column x-positions for each element kind, font family, and transition
//  right-alignment.
//
//  Technique: `PDFDocument.findString` returns PDFSelection objects whose
//  `bounds(for:)` gives the glyph rect in page coordinates (origin is the
//  page's lower-left per PDF convention). We pin element positions to the
//  renderer's own Indent/BlockWidth constants (Courier 12pt ≈ 7.2pt/char).
//
//  Tolerances are 4pt unless stated; tighter than that breaks on minor
//  PDFKit rounding across OS versions.
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
import PDFKit
@testable import PenovaKit
@testable import Penova

@MainActor
@Suite struct PDFLayoutTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    /// Insert a scene with one element of every non-heading kind, each
    /// carrying a unique marker we can findString by.
    private func makeOneOfEachProject(ctx: ModelContext) -> Project {
        let p = Project(title: "Layout")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "Kitchen", location: .interior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let h = SceneElement(kind: .heading, text: s.heading, order: 0)
        let a = SceneElement(kind: .action, text: "ACTIONMARK", order: 1)
        let c = SceneElement(kind: .character, text: "CHARMARK", order: 2)
        let par = SceneElement(kind: .parenthetical, text: "parenmark", order: 3)
        let d = SceneElement(kind: .dialogue, text: "DIALOGMARK", order: 4, characterName: "CHARMARK")
        let t = SceneElement(kind: .transition, text: "TRANSMARK", order: 5)
        for el in [h, a, c, par, d, t] {
            el.scene = s; s.elements.append(el); ctx.insert(el)
        }
        return p
    }

    /// Locate the first rect of the first occurrence of `needle` in the
    /// document, or nil if not present.
    private func boundsOf(_ needle: String, in doc: PDFDocument) -> (pageIndex: Int, rect: CGRect)? {
        let sels = doc.findString(needle, withOptions: .literal)
        guard let sel = sels.first, let page = sel.pages.first else { return nil }
        return (doc.index(for: page), sel.bounds(for: page))
    }

    // MARK: - Page size

    @Test func everyPageIsUSLetter() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = makeOneOfEachProject(ctx: ctx)
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else {
            Issue.record("Could not open PDF"); return
        }
        #expect(doc.pageCount >= 2)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            #expect(box.width == 612, "page \(i) width \(box.width)")
            #expect(box.height == 792, "page \(i) height \(box.height)")
        }
    }

    // MARK: - Column positions

    @Test func actionLeftEdgeAtOnePointFiveInches() throws {
        let container = try makeContainer()
        let p = makeOneOfEachProject(ctx: container.mainContext)
        try container.mainContext.save()
        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url),
              let hit = boundsOf("ACTIONMARK", in: doc) else {
            Issue.record("action not found"); return
        }
        #expect(abs(hit.rect.minX - 108) <= 4, "action x=\(hit.rect.minX), expected 108 (1.5\")")
    }

    @Test func characterCueLeftEdgeAtThreePointSevenInches() throws {
        let container = try makeContainer()
        let p = makeOneOfEachProject(ctx: container.mainContext)
        try container.mainContext.save()
        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url),
              let hit = boundsOf("CHARMARK", in: doc) else {
            Issue.record("character cue not found"); return
        }
        // Indent.character = 266pt (3.7")
        #expect(abs(hit.rect.minX - 266) <= 4, "char x=\(hit.rect.minX), expected 266 (3.7\")")
    }

    @Test func dialogueLeftEdgeAtTwoPointFiveInches() throws {
        let container = try makeContainer()
        let p = makeOneOfEachProject(ctx: container.mainContext)
        try container.mainContext.save()
        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url),
              let hit = boundsOf("DIALOGMARK", in: doc) else {
            Issue.record("dialogue not found"); return
        }
        #expect(abs(hit.rect.minX - 180) <= 4, "dialog x=\(hit.rect.minX), expected 180 (2.5\")")
    }

    @Test func parentheticalOpensAtThreePointOneInches() throws {
        // parenthetical content is drawn from x = Indent.parens (224pt).
        // "(parenmark)" → the opening paren sits at 224; find "(" to verify.
        let container = try makeContainer()
        let p = makeOneOfEachProject(ctx: container.mainContext)
        try container.mainContext.save()
        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url),
              let hit = boundsOf("(parenmark)", in: doc) else {
            Issue.record("parenthetical not found"); return
        }
        #expect(abs(hit.rect.minX - 224) <= 4, "parens x=\(hit.rect.minX), expected 224 (3.1\")")
    }

    // MARK: - Transition right alignment

    @Test func transitionIsRightAlignedToSevenPointFiveInches() throws {
        // drawRightAligned draws in a box at x=108 width=432, .right-aligned.
        // "TRANSMARK" uppercased gets a ":" suffix → 10 chars × ~7.2pt = 72pt.
        // Rightmost glyph sits at 108+432 = 540pt.
        let container = try makeContainer()
        let p = makeOneOfEachProject(ctx: container.mainContext)
        try container.mainContext.save()
        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url),
              let hit = boundsOf("TRANSMARK:", in: doc) else {
            Issue.record("transition not found"); return
        }
        let rightEdge = hit.rect.maxX
        #expect(abs(rightEdge - 540) <= 4, "transition right=\(rightEdge), expected 540 (7.5\")")
        // And it is NOT at the left margin.
        #expect(hit.rect.minX > 400, "transition left=\(hit.rect.minX) unexpectedly near left margin")
    }

    // MARK: - Scene-number gutters (left 0.5", right edge 0.5" from right page)

    @Test func sceneNumberGutterAppearsInLeftAndRightGutters() throws {
        // Left gutter: renderer draws "N." at x=36 (no paragraph alignment).
        // Right gutter: drawn right-aligned in a box whose rightmost x = 576.
        // We search for "1." and inspect the two hits.
        let container = try makeContainer()
        let p = makeOneOfEachProject(ctx: container.mainContext)
        try container.mainContext.save()
        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else { Issue.record("no doc"); return }
        let sels = doc.findString("1.", withOptions: .literal)

        var sawLeftGutter = false
        var sawRightGutter = false
        for sel in sels {
            for page in sel.pages {
                let r = sel.bounds(for: page)
                // Only consider script pages.
                if doc.index(for: page) == 0 { continue }
                if abs(r.minX - 36) <= 6 { sawLeftGutter = true }
                if abs(r.maxX - 576) <= 6 { sawRightGutter = true }
            }
        }
        #expect(sawLeftGutter, "no '1.' at left gutter (x≈36)")
        #expect(sawRightGutter, "no '1.' at right gutter (maxX≈576)")
    }

    // MARK: - Font

    @Test func rendererEmitsCourierGlyphs() throws {
        // PDFKit surfaces the font on any selection's attributedString.
        let container = try makeContainer()
        let p = makeOneOfEachProject(ctx: container.mainContext)
        try container.mainContext.save()
        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url),
              let sel = doc.findString("ACTIONMARK", withOptions: .literal).first,
              let attr = sel.attributedString, attr.length > 0 else {
            Issue.record("no attributed selection"); return
        }
        var sawCourier = false
        attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            if let font = value as? UIFont,
               font.fontName.lowercased().contains("courier") {
                sawCourier = true
            }
        }
        #expect(sawCourier, "expected Courier font on rendered text")
    }

    // MARK: - Long-action wrap (does not exceed right margin of action column)

    @Test func longActionWrapsWithinActionColumn() throws {
        // Action column: x=108 width=432 → rightmost allowed maxX ≈ 540.
        // Give a very long line with many short words so the wrapper splits it
        // into many lines. We scan each rendered line fragment by findString
        // on a unique marker on every "line" we construct — simpler: search
        // a unique substring and verify each of its occurrences lies in-column.
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Wrap")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "Field", location: .exterior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let h = SceneElement(kind: .heading, text: s.heading, order: 0)
        h.scene = s; s.elements.append(h); ctx.insert(h)
        // Repeat a unique token with filler so the wrapper has to break.
        let filler = "wind through grass and sky "
        let text = String(repeating: "WRAPTOKEN \(filler)", count: 15)
        let a = SceneElement(kind: .action, text: text, order: 1)
        a.scene = s; s.elements.append(a); ctx.insert(a)
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else { Issue.record("no doc"); return }
        let sels = doc.findString("WRAPTOKEN", withOptions: .literal)
        #expect(sels.count >= 2, "expected multiple wrapped lines; got \(sels.count)")
        for sel in sels {
            for page in sel.pages {
                if doc.index(for: page) == 0 { continue }
                let r = sel.bounds(for: page)
                // The token itself is 9 chars ≈ 65pt; its leftmost must be at
                // or after the action indent (108).
                #expect(r.minX >= 106, "WRAPTOKEN left=\(r.minX) before action column")
                #expect(r.maxX <= 542, "WRAPTOKEN right=\(r.maxX) exceeds right margin")
            }
        }
    }
}
