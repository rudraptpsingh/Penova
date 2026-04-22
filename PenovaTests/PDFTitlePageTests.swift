//
//  PDFTitlePageTests.swift
//  PenovaTests
//
//  Title-page layout + page numbering conventions.
//
//  Verified against ScriptPDFRenderer.swift:
//    - project.title is uppercased and drawn via .center paragraph style
//      across the full 612pt page width at y = pageHeight * 0.38.
//    - "Written by" follows 4 lines below; author 2 lines below that.
//    - Non-empty contactBlock is drawn at x=Margins.left (108pt), y set so
//      the box sits 1" above the page bottom (i.e. in the bottom half).
//    - Page numbers: title page unnumbered; first script page unnumbered;
//      subsequent script pages render "N." with right edge at pageWidth-72
//      (=540) at y=36 from the top (PDF y ≈ 746..756).
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
import PDFKit
@testable import Penova

@MainActor
@Suite struct PDFTitlePageTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    private func renderedDoc(
        title: String,
        author: String? = "Jane Writer",
        contact: String = "",
        scenes: Int = 1,
        ctx: ModelContext
    ) throws -> (URL, PDFDocument, Project) {
        if let author {
            UserDefaults.standard.set(author, forKey: "penova.auth.fullName")
        } else {
            UserDefaults.standard.removeObject(forKey: "penova.auth.fullName")
        }
        let p = Project(title: title)
        p.contactBlock = contact
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<scenes {
            let s = ScriptScene(locationName: "Loc \(i)", location: .interior, time: .day, order: i)
            s.episode = ep; ep.scenes.append(s); ctx.insert(s)
            let h = SceneElement(kind: .heading, text: s.heading, order: 0)
            h.scene = s; s.elements.append(h); ctx.insert(h)
            let a = SceneElement(kind: .action, text: "A beat.", order: 1)
            a.scene = s; s.elements.append(a); ctx.insert(a)
        }
        try ctx.save()
        let url = try ScriptPDFRenderer.render(project: p)
        guard let doc = PDFDocument(url: url) else {
            Issue.record("could not open rendered PDF")
            throw CocoaError(.fileReadUnknown)
        }
        return (url, doc, p)
    }

    private func firstBounds(
        of needle: String, in doc: PDFDocument
    ) -> (pageIndex: Int, rect: CGRect)? {
        guard let sel = doc.findString(needle, withOptions: .literal).first,
              let page = sel.pages.first else { return nil }
        return (doc.index(for: page), sel.bounds(for: page))
    }

    // MARK: - Title text

    @Test func projectTitleUppercasedOnTitlePage() throws {
        let container = try makeContainer()
        let (url, doc, _) = try renderedDoc(title: "The Quiet Year",
                                            ctx: container.mainContext)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let hit = firstBounds(of: "THE QUIET YEAR", in: doc) else {
            Issue.record("uppercase title not found"); return
        }
        #expect(hit.pageIndex == 0, "title not on page 0 (title page)")
        // And mixed-case form is NOT present.
        #expect(doc.findString("The Quiet Year", withOptions: .literal).isEmpty)
    }

    @Test func titleIsHorizontallyCenteredOnPage() throws {
        let container = try makeContainer()
        let (url, doc, _) = try renderedDoc(title: "CENTERED",
                                            ctx: container.mainContext)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let hit = firstBounds(of: "CENTERED", in: doc) else {
            Issue.record("title not found"); return
        }
        let mid = (hit.rect.minX + hit.rect.maxX) / 2
        // Page width 612, horizontal midpoint 306.
        #expect(abs(mid - 306) <= 4, "title midpoint=\(mid), expected ≈306")
    }

    @Test func writtenByAndAuthorNameRenderWhenSet() throws {
        let container = try makeContainer()
        let (url, doc, _) = try renderedDoc(title: "X",
                                            author: "Ada Lovelace",
                                            ctx: container.mainContext)
        defer { try? FileManager.default.removeItem(at: url) }
        let by = firstBounds(of: "Written by", in: doc)
        let name = firstBounds(of: "Ada Lovelace", in: doc)
        #expect(by?.pageIndex == 0, "Written by not on title page")
        #expect(name?.pageIndex == 0, "author not on title page")
        // Author baseline sits below "Written by" (PDF y smaller).
        if let by, let name {
            #expect(name.rect.minY < by.rect.minY,
                    "author y=\(name.rect.minY) expected below 'Written by' y=\(by.rect.minY)")
        }
    }

    // MARK: - Contact block

    @Test func contactBlockOnBottomHalfAndAtLeftMargin() throws {
        let container = try makeContainer()
        let (url, doc, _) = try renderedDoc(title: "Contact",
                                            contact: "me@x.com\n+1 555 0100",
                                            ctx: container.mainContext)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let hit = firstBounds(of: "me@x.com", in: doc) else {
            Issue.record("contact line not found"); return
        }
        #expect(hit.pageIndex == 0, "contact not on title page")
        // Bottom half in PDF coords = y < 396.
        #expect(hit.rect.minY < 396, "contact y=\(hit.rect.minY) not in bottom half")
        // Left margin at 108pt.
        #expect(abs(hit.rect.minX - 108) <= 4, "contact x=\(hit.rect.minX) not at left margin")
    }

    @Test func emptyContactBlockOmitted() throws {
        let container = try makeContainer()
        let (url, doc, _) = try renderedDoc(title: "Ghost",
                                            contact: "",
                                            ctx: container.mainContext)
        defer { try? FileManager.default.removeItem(at: url) }
        // With a blank contact, no stray marker text should be on title page.
        #expect(doc.findString("@", withOptions: .literal).isEmpty,
                "no contact text expected but found @ characters")
    }

    // MARK: - Page numbering

    @Test func titlePageIsUnnumbered() throws {
        // No "1." , "2." or "3." should appear on the title page.
        let container = try makeContainer()
        let (url, doc, _) = try renderedDoc(title: "NoNum", scenes: 1,
                                            ctx: container.mainContext)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let titlePage = doc.page(at: 0) else { Issue.record("no title page"); return }
        for needle in ["1.", "2.", "3."] {
            let sels = doc.findString(needle, withOptions: .literal)
            for sel in sels {
                for p in sel.pages {
                    #expect(p != titlePage, "'\(needle)' unexpectedly on title page")
                }
            }
        }
    }

    @Test func firstScriptPageHasNoTopRightPageNumber() throws {
        let container = try makeContainer()
        let (url, doc, _) = try renderedDoc(title: "One", scenes: 1,
                                            ctx: container.mainContext)
        defer { try? FileManager.default.removeItem(at: url) }
        guard doc.pageCount >= 2, let scriptPage = doc.page(at: 1) else {
            Issue.record("no script page"); return
        }
        // If "1." appeared at the top-right header strip, the first page
        // would be numbered (contrary to the renderer contract).
        let sels = doc.findString("1.", withOptions: .literal)
        for sel in sels where sel.pages.contains(scriptPage) {
            let r = sel.bounds(for: scriptPage)
            // Top strip (PDF y > 720) + right-aligned (maxX ≈ 540).
            let inTopStrip = r.minY > 720
            let atRightEdge = abs(r.maxX - 540) <= 6
            #expect(!(inTopStrip && atRightEdge),
                    "first script page unexpectedly has top-right '1.' at \(r)")
        }
    }

    @Test func secondScriptPageHasTopRightPageNumber() throws {
        // Force a second script page by flooding actions.
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Overflow")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "Room", location: .interior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let h = SceneElement(kind: .heading, text: s.heading, order: 0)
        h.scene = s; s.elements.append(h); ctx.insert(h)
        for i in 0..<80 {
            let a = SceneElement(kind: .action, text: "Line \(i) fires.", order: i + 1)
            a.scene = s; s.elements.append(a); ctx.insert(a)
        }
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url), doc.pageCount >= 3,
              let secondScript = doc.page(at: 2) else {
            Issue.record("needed a second script page"); return
        }
        // Look for "2." on that page in the header strip at the right edge.
        let sels = doc.findString("2.", withOptions: .literal)
        var found = false
        for sel in sels where sel.pages.contains(secondScript) {
            let r = sel.bounds(for: secondScript)
            if r.minY > 720 && abs(r.maxX - 540) <= 6 {
                found = true; break
            }
        }
        #expect(found, "expected top-right '2.' on second script page")
    }

    // MARK: - measurePageCount excludes the title page

    @Test func measurePageCountEqualsRenderedMinusTitle() throws {
        let container = try makeContainer()
        let (url, doc, project) = try renderedDoc(title: "MTP", scenes: 3,
                                                  ctx: container.mainContext)
        defer { try? FileManager.default.removeItem(at: url) }
        let measured = ScriptPDFRenderer.measurePageCount(project: project)
        #expect(measured >= 1)
        #expect(doc.pageCount == measured + 1,
                "rendered=\(doc.pageCount) measured=\(measured) (must differ by 1 title page)")
    }
}
