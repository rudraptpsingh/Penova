//
//  PDFRevisionStripeTests.swift
//  PenovaTests
//
//  Verifies the on-page revision indicators emitted by
//  ScreenplayPDFRenderer for production-locked projects with active
//  revisions: header slug + asterisks. (The colored stripe is a fill
//  rect — not extractable as text — so it's covered by
//  RevisionPageTests' plan-mode check rather than here.)
//

import Testing
import Foundation
import SwiftData
import PDFKit
@testable import PenovaKit
@testable import Penova

@MainActor
@Suite struct PDFRevisionStripeTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self,
            SceneElement.self, ScriptCharacter.self, WritingDay.self, Revision.self,
            configurations: config
        )
    }

    private func renderToTempURL(_ project: Project) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("revstripe-\(UUID().uuidString.prefix(6)).pdf")
        try? FileManager.default.removeItem(at: url)
        return try ScreenplayPDFRenderer.render(project: project, to: url)
    }

    private func pageStrings(for url: URL) -> [String] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).map { i in
            doc.page(at: i)?.string ?? ""
        }
    }

    // MARK: - Slug presence

    @Test func slugAppearsOnRevisionPage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Acme Pilot"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)

        let s = ScriptScene(locationName: "ROOM", location: .interior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let a = SceneElement(kind: .action, text: "She turns. New beat.", order: 0)
        a.scene = s; s.elements.append(a); ctx.insert(a)

        p.lock()
        let rev = Revision(label: "Blue Revision", fountainSnapshot: "",
                           authorName: "Test", sceneCountAtSave: 1, wordCountAtSave: 0,
                           color: .blue, roundNumber: 2)
        rev.project = p; p.revisions.append(rev); ctx.insert(rev)
        a.lastRevisedRevisionID = rev.id   // stamp the only element
        try ctx.save()

        let url = try renderToTempURL(p)
        defer { try? FileManager.default.removeItem(at: url) }

        let strings = pageStrings(for: url)
        // Title page (index 0) is suppressed; the slug should appear
        // on at least the body page (index 1).
        let bodyPagesText = strings.dropFirst().joined(separator: "\n")
        #expect(bodyPagesText.contains("Blue Revision"),
                "header slug should appear on the revision body page")
        #expect(bodyPagesText.contains("ACME PILOT"),
                "slug includes uppercased project title")
    }

    @Test func slugSuppressedOnUnlockedProject() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Acme Pilot"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "ROOM", location: .interior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let a = SceneElement(kind: .action, text: "She turns.", order: 0)
        a.scene = s; s.elements.append(a); ctx.insert(a)

        // NOT locked.
        let rev = Revision(label: "Blue Revision", fountainSnapshot: "",
                           authorName: "Test", sceneCountAtSave: 1, wordCountAtSave: 0,
                           color: .blue, roundNumber: 2)
        rev.project = p; p.revisions.append(rev); ctx.insert(rev)
        a.lastRevisedRevisionID = rev.id
        try ctx.save()

        let url = try renderToTempURL(p)
        defer { try? FileManager.default.removeItem(at: url) }
        let bodyText = pageStrings(for: url).dropFirst().joined(separator: "\n")
        #expect(!bodyText.contains("Blue Revision"),
                "unlocked projects must NOT print the revision slug")
    }

    @Test func cleanPageHasNoSlug() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Clean Pilot"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "ROOM", location: .interior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let a = SceneElement(kind: .action, text: "Quiet.", order: 0)
        a.scene = s; s.elements.append(a); ctx.insert(a)
        p.lock()
        let rev = Revision(label: "Blue Revision", fountainSnapshot: "",
                           authorName: "Test", sceneCountAtSave: 1, wordCountAtSave: 0,
                           color: .blue, roundNumber: 2)
        rev.project = p; p.revisions.append(rev); ctx.insert(rev)
        // Note: no element stamped → page is clean.
        try ctx.save()

        let url = try renderToTempURL(p)
        defer { try? FileManager.default.removeItem(at: url) }
        let bodyText = pageStrings(for: url).dropFirst().joined(separator: "\n")
        #expect(!bodyText.contains("Blue Revision"),
                "clean revision page must not show the slug")
    }

    // MARK: - Asterisk presence (consolidation rule)

    @Test func consolidationCollapsesLongDialogueBlock() {
        // Build a Character + Parenthetical + Dialogue + Dialogue + Dialogue
        // block where all five are stamped against the active revision.
        // Consolidation rule: the four non-character rows must be
        // suppressed; only the leading character cue keeps its mark.
        let s = ScriptScene(locationName: "X", location: .interior, time: .day, order: 0)
        let revID = "REV-1"
        let elements: [(SceneElementKind, String)] = [
            (.character, "ANNA"),
            (.parenthetical, "(softly)"),
            (.dialogue, "I never said that."),
            (.dialogue, "Not exactly."),
            (.dialogue, "Maybe with my eyes."),
        ]
        for (i, (kind, text)) in elements.enumerated() {
            let e = SceneElement(kind: kind, text: text, order: i)
            e.lastRevisedRevisionID = revID
            e.scene = s
            s.elements.append(e)
        }

        let suppressed = ScreenplayPDFRenderer.testSuppressionMap(
            scene: s, activeRevisionID: revID
        )
        // 4 of the 5 rows should be suppressed (everything but the cue).
        #expect(suppressed.count == 4)
        // Leading character cue is NOT suppressed.
        let cueID = s.elementsOrdered.first { $0.kind == .character }!.id
        #expect(!suppressed.contains(cueID),
                "leading character cue carries the consolidated mark")
    }

    @Test func consolidationLeavesShortBlockUntouched() {
        // CHARACTER + DIALOGUE — only 2 rows, fewer than the 3-line
        // threshold. Each row keeps its own asterisk.
        let s = ScriptScene(locationName: "X", location: .interior, time: .day, order: 0)
        let revID = "REV-1"
        let pairs: [(SceneElementKind, String)] = [
            (.character, "ANNA"),
            (.dialogue, "Hi."),
        ]
        for (i, (kind, text)) in pairs.enumerated() {
            let e = SceneElement(kind: kind, text: text, order: i)
            e.lastRevisedRevisionID = revID
            e.scene = s
            s.elements.append(e)
        }
        let suppressed = ScreenplayPDFRenderer.testSuppressionMap(
            scene: s, activeRevisionID: revID
        )
        #expect(suppressed.isEmpty,
                "blocks below 3-line threshold must not consolidate")
    }
}
