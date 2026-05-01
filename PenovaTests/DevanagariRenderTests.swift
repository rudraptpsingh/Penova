//
//  DevanagariRenderTests.swift
//  PenovaTests
//
//  Penova ships Hindi (हिन्दी) as a Voice Quick Capture locale and the
//  app's audience includes Indian screenwriters, so Hindi script content
//  has to render in PDF (and round-trip back from PDF) without dropped
//  glyphs. UIKit's text-rendering pipeline auto-cascades to a system
//  Devanagari font when the primary Courier font lacks the glyphs, so
//  the renderer should "just work" — but the cost of a regression here
//  is silent (boxes in the PDF). These tests pin the behaviour.
//

import Testing
import Foundation
import SwiftData
import PDFKit
@testable import Penova
@testable import PenovaKit

@MainActor
@Suite struct DevanagariRenderTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self,
            SceneElement.self, ScriptCharacter.self, WritingDay.self,
            configurations: config
        )
    }

    private func renderProject(
        title: String,
        action: String,
        cue: String,
        dialogue: String,
        ctx: ModelContext
    ) throws -> URL {
        let p = Project(title: title); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "रसोई", location: .interior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let elements: [(SceneElementKind, String)] = [
            (.heading, s.heading),
            (.action, action),
            (.character, cue),
            (.dialogue, dialogue),
        ]
        for (i, pair) in elements.enumerated() {
            let el = SceneElement(kind: pair.0, text: pair.1, order: i)
            el.scene = s; s.elements.append(el); ctx.insert(el)
        }
        try ctx.save()
        return try ScriptPDFRenderer.render(project: p)
    }

    // MARK: - Title page Hindi

    @Test func devanagariTitleSurvivesPDFExtraction() throws {
        let container = try makeContainer()
        let url = try renderProject(
            title: "मुंबई की रात",          // "Mumbai's Night"
            action: "रवि चाय बनाता है।",
            cue: "रवि",
            dialogue: "अरे यार, क्या हो गया?",
            ctx: container.mainContext
        )
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else {
            Issue.record("rendered PDF unreadable"); return
        }
        // Find at least one occurrence of the Hindi project title.
        let hits = doc.findString("मुंबई", withOptions: .literal)
        #expect(!hits.isEmpty,
                "Devanagari title 'मुंबई' missing from rendered PDF — Courier dropped glyphs without falling back")
    }

    // MARK: - Body content Hindi

    @Test func devanagariActionSurvivesPDFExtraction() throws {
        let container = try makeContainer()
        let url = try renderProject(
            title: "Mixed Script",
            action: "रवि चाय बनाता है।",        // Devanagari action line
            cue: "RAVI",
            dialogue: "Yaar.",
            ctx: container.mainContext
        )
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else {
            Issue.record("rendered PDF unreadable"); return
        }
        // PDFKit's `findString` is brittle around Devanagari conjunct
        // boundaries — read via PDFKitLineSource (same path the parser
        // uses) and check the text actually made it into the body.
        let allText = (0..<doc.pageCount)
            .flatMap { PDFKitLineSource(document: doc).lines(onPage: $0) }
            .map(\.text)
            .joined(separator: " ")
        #expect(allText.contains("चाय"),
                "Devanagari action body lost on render; got: \(allText)")
        #expect(allText.contains("बनाता"),
                "Devanagari action body lost on render; got: \(allText)")
    }

    @Test func devanagariDialogueSurvivesPDFExtraction() throws {
        let container = try makeContainer()
        let url = try renderProject(
            title: "Dialogue Test",
            action: "Action.",
            cue: "रवि",
            dialogue: "क्या हो गया",        // Devanagari dialogue
            ctx: container.mainContext
        )
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else {
            Issue.record("rendered PDF unreadable"); return
        }
        let hits = doc.findString("क्या हो गया", withOptions: .literal)
        #expect(!hits.isEmpty,
                "Devanagari dialogue body lost on render")
    }

    // MARK: - Round-trip via PDFKitLineSource + parser

    @Test func devanagariRoundTripsThroughParser() throws {
        let container = try makeContainer()
        let url = try renderProject(
            title: "RT",
            action: "एक छोटा सा कमरा।",
            cue: "मीना",
            dialogue: "ठीक है।",
            ctx: container.mainContext
        )
        defer { try? FileManager.default.removeItem(at: url) }
        guard let pdf = PDFDocument(url: url) else {
            Issue.record("rendered PDF unreadable"); return
        }
        let result = PDFScreenplayParser.parse(PDFKitLineSource(document: pdf))
        let allText = result.document.scenes.flatMap { $0.elements }
            .map(\.text)
            .joined(separator: "  ")
        #expect(allText.contains("एक छोटा"),
                "Devanagari action lost in re-parse; got: \(allText)")
        #expect(allText.contains("मीना"),
                "Devanagari character cue lost in re-parse")
        #expect(allText.contains("ठीक है"),
                "Devanagari dialogue lost in re-parse")
    }

    // MARK: - Heading with Devanagari location

    @Test func devanagariLocationHeadingRenders() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Loc"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "मरीन ड्राइव", location: .exterior, time: .evening, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let h = SceneElement(kind: .heading, text: s.heading, order: 0)
        h.scene = s; s.elements.append(h); ctx.insert(h)
        let a = SceneElement(kind: .action, text: "Action.", order: 1)
        a.scene = s; s.elements.append(a); ctx.insert(a)
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else {
            Issue.record("rendered PDF unreadable"); return
        }
        let hits = doc.findString("मरीन", withOptions: .literal)
        #expect(!hits.isEmpty,
                "Devanagari heading 'मरीन ड्राइव' lost on render")
    }
}
