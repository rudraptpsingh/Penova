//
//  MacPDFRenderTests.swift
//  PenovaMacTests
//
//  Verifies the Mac PDF renderer:
//  - Produces a non-empty, valid PDF on disk
//  - Loads back via PDFKit / CGPDFDocument
//  - Reports a sensible page count
//  - Page count agrees with the layout-engine measure (round-trip)
//  - Cross-platform layout constants from PenovaKit are wired correctly
//

import Testing
import Foundation
import PDFKit
import CoreGraphics
import SwiftData
@testable import PenovaKit

@Suite("Mac PDF renderer")
struct MacPDFRenderTests {

    private static func freshContext() throws -> ModelContext {
        let schema = Schema(PenovaSchema.models)
        let config = ModelConfiguration("pdf-test", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Layout constants must match what the iOS renderer uses. If
    /// anyone tweaks these numbers without updating both renderers,
    /// this test fails first.
    @Test("Layout spec constants match WGA convention")
    func specConstants() {
        #expect(ScreenplayLayoutSpec.pageWidth == 612)
        #expect(ScreenplayLayoutSpec.pageHeight == 792)
        #expect(ScreenplayLayoutSpec.Margins.top == 72)
        #expect(ScreenplayLayoutSpec.Margins.left == 108)  // 1.5"
        #expect(ScreenplayLayoutSpec.Indent.character == 266)  // 3.7"
        #expect(ScreenplayLayoutSpec.Indent.dialogue == 180)   // 2.5"
        #expect(ScreenplayLayoutSpec.bodyFontSize == 12)
        #expect(ScreenplayLayoutSpec.linesPerPage == 55)
    }

    /// Empty project (no episodes) renders as 0 pages — measure path.
    @Test("Empty project measures as 0 script pages")
    func emptyProjectMeasures() throws {
        let ctx = try Self.freshContext()
        let p = Project(title: "Empty")
        ctx.insert(p)
        try ctx.save()
        #expect(ScreenplayPDFRenderer.measurePageCount(project: p) == 0)
    }

    /// The kitchen scene from the sample library produces 1+ script
    /// pages and writes a real PDF on disk that loads via PDFKit.
    @Test("Sample project produces a valid PDF on disk")
    func sampleProjectRenders() throws {
        let ctx = try Self.freshContext()
        SeedFixtures.installSample(in: ctx)
        let project = try #require(try ctx.fetch(FetchDescriptor<Project>()).first)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("penova-test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try ScreenplayPDFRenderer.render(project: project, to: url)

        // File exists and has bytes
        let data = try Data(contentsOf: url)
        #expect(data.count > 1024, "PDF file is too small to be valid: \(data.count) bytes")

        // Loads via PDFKit
        let pdf = try #require(PDFDocument(url: url))
        #expect(pdf.pageCount >= 2, "Expected title + at least one script page")

        // Title page is unnumbered, but PDFDocument counts every page
        let scriptPages = ScreenplayPDFRenderer.measurePageCount(project: project)
        #expect(scriptPages >= 1)
        #expect(pdf.pageCount == scriptPages + 1, // +1 for the title page
                "PDFKit page count (\(pdf.pageCount)) should equal script pages \(scriptPages) + title page (1)")
    }

    /// Render output should contain the kitchen scene's heading text.
    @Test("Rendered PDF contains the kitchen scene heading")
    func pdfContainsKitchenHeading() throws {
        let ctx = try Self.freshContext()
        SeedFixtures.installSample(in: ctx)
        let project = try #require(try ctx.fetch(FetchDescriptor<Project>()).first)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("penova-text-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try ScreenplayPDFRenderer.render(project: project, to: url)

        let pdf = try #require(PDFDocument(url: url))
        let text = pdf.string ?? ""
        #expect(text.contains("KITCHEN"), "PDF text didn't include the kitchen heading")
        #expect(text.contains("PENNY"))
        #expect(text.contains("MARCUS"))
    }

    /// Calling render twice with the same project should produce
    /// PDFs of the same page count — the renderer must be deterministic.
    @Test("Renderer is deterministic across runs")
    func deterministic() throws {
        let ctx = try Self.freshContext()
        SeedFixtures.installSample(in: ctx)
        let project = try #require(try ctx.fetch(FetchDescriptor<Project>()).first)

        let url1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("p1-\(UUID().uuidString).pdf")
        let url2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("p2-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        try ScreenplayPDFRenderer.render(project: project, to: url1)
        try ScreenplayPDFRenderer.render(project: project, to: url2)

        let p1 = try #require(PDFDocument(url: url1))
        let p2 = try #require(PDFDocument(url: url2))
        #expect(p1.pageCount == p2.pageCount)
    }

    /// Running the measure path twice must agree.
    @Test("Measure is idempotent")
    func measureIdempotent() throws {
        let ctx = try Self.freshContext()
        SeedFixtures.installSample(in: ctx)
        let project = try #require(try ctx.fetch(FetchDescriptor<Project>()).first)

        let m1 = ScreenplayPDFRenderer.measurePageCount(project: project)
        let m2 = ScreenplayPDFRenderer.measurePageCount(project: project)
        #expect(m1 == m2)
    }
}
