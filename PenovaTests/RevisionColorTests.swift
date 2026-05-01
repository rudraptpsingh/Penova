//
//  RevisionColorTests.swift
//  PenovaTests
//
//  WGA-standard revision color sequence:
//   White → Blue → Pink → Yellow → Green → Goldenrod → Buff → Salmon
//   → Cherry → (wrap to White).
//
//  Productions reference these colors verbatim ("we're on the green
//  pages") so the order must NEVER change. These tests pin the
//  sequence and the project-level helpers that auto-pick the next
//  color and round number.
//

import Testing
import Foundation
import SwiftData
@testable import Penova
@testable import PenovaKit

@MainActor
@Suite struct RevisionColorTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self,
            SceneElement.self, ScriptCharacter.self, WritingDay.self, Revision.self,
            configurations: config
        )
    }

    // MARK: - Sequence pinned

    @Test func wgaColorSequencePinned() {
        // ALL CASES order must match WGA / Final Draft / Movie Magic
        // Screenwriter convention exactly. After Cherry the rotation
        // continues through Tan, Ivory, then "Double White / Double
        // Blue / …" to Double Cherry before wrapping back to White.
        let expected: [RevisionColor] = [
            .white, .blue, .pink, .yellow, .green,
            .goldenrod, .buff, .salmon, .cherry,
            .tan, .ivory,
            .doubleWhite, .doubleBlue, .doublePink, .doubleYellow, .doubleGreen,
            .doubleGoldenrod, .doubleBuff, .doubleSalmon, .doubleCherry
        ]
        #expect(RevisionColor.allCases == expected,
                "WGA revision color order changed — productions reference these names")
    }

    @Test func nextSteppingThroughSequence() {
        var c: RevisionColor = .white
        let observed = (0..<RevisionColor.allCases.count).map { _ -> RevisionColor in
            let cur = c; c = c.next; return cur
        }
        #expect(observed == RevisionColor.allCases)
    }

    @Test func nextWrapsAfterDoubleCherryBackToWhite() {
        // Cherry → Tan (no longer wraps to White; the cycle is extended).
        #expect(RevisionColor.cherry.next == .tan)
        #expect(RevisionColor.tan.next == .ivory)
        #expect(RevisionColor.ivory.next == .doubleWhite)
        // The full cycle now wraps after doubleCherry.
        #expect(RevisionColor.doubleCherry.next == .white)
    }

    @Test func displayLabelIsCapitalised() {
        #expect(RevisionColor.white.display == "White")
        #expect(RevisionColor.goldenrod.display == "Goldenrod")
        #expect(RevisionColor.doubleBlue.display == "Double Blue")
        #expect(RevisionColor.doubleCherry.display == "Double Cherry")
    }

    // MARK: - Project helpers

    @Test func firstRevisionInProjectIsWhite() throws {
        let container = try makeContainer()
        let p = Project(title: "P"); container.mainContext.insert(p)
        try container.mainContext.save()
        #expect(p.nextRevisionColor() == .white)
        #expect(p.nextRevisionRoundNumber() == 1)
    }

    @Test func nextColorAdvancesFromMostRecent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let r1 = Revision(label: "R1", fountainSnapshot: "", authorName: "",
                          sceneCountAtSave: 0, wordCountAtSave: 0,
                          color: .white, roundNumber: 1)
        r1.project = p; p.revisions.append(r1); ctx.insert(r1)
        try ctx.save()
        #expect(p.nextRevisionColor() == .blue)
        #expect(p.nextRevisionRoundNumber() == 2)
    }

    @Test func nextColorPicksMostRecentByCreatedAt() throws {
        // Inserting an older revision after a newer one must not flip
        // the next color back. Helps when revisions are imported out
        // of order (e.g. from FDX import).
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)

        // A blue revision created 1 hour ago.
        let blue = Revision(label: "Blue 1h ago", fountainSnapshot: "",
                            authorName: "", sceneCountAtSave: 0, wordCountAtSave: 0,
                            color: .blue, roundNumber: 2)
        blue.project = p; blue.createdAt = Date().addingTimeInterval(-3600)
        p.revisions.append(blue); ctx.insert(blue)

        // A pink revision created 30 min ago (more recent → newest).
        let pink = Revision(label: "Pink 30m ago", fountainSnapshot: "",
                            authorName: "", sceneCountAtSave: 0, wordCountAtSave: 0,
                            color: .pink, roundNumber: 3)
        pink.project = p; pink.createdAt = Date().addingTimeInterval(-1800)
        p.revisions.append(pink); ctx.insert(pink)

        try ctx.save()
        #expect(p.nextRevisionColor() == .yellow,
                "expected next-after-pink = yellow")
        #expect(p.nextRevisionRoundNumber() == 4)
    }

    @Test func roundNumberAlwaysIncreasesAfterFullCycleWrap() throws {
        // After a full color cycle (white → … → doubleCherry), color
        // wraps back to white but round number keeps climbing. So the
        // revision after a full cycle of N revisions should be white +
        // round N+1.
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Long"); ctx.insert(p)
        let allColors = RevisionColor.allCases
        for (i, c) in allColors.enumerated() {
            let r = Revision(label: "R\(i + 1)", fountainSnapshot: "",
                             authorName: "", sceneCountAtSave: 0, wordCountAtSave: 0,
                             color: c, roundNumber: i + 1)
            r.project = p; r.createdAt = Date().addingTimeInterval(Double(i))
            p.revisions.append(r); ctx.insert(r)
        }
        try ctx.save()
        #expect(p.nextRevisionColor() == .white, "color wraps after full cycle")
        #expect(p.nextRevisionRoundNumber() == allColors.count + 1,
                "round keeps climbing")
    }

    // MARK: - Persistence

    @Test func revisionColorPersistsThroughSave() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let r = Revision(label: "Goldenrod first draft",
                         fountainSnapshot: "INT. ROOM\n",
                         authorName: "Test", sceneCountAtSave: 1, wordCountAtSave: 5,
                         color: .goldenrod, roundNumber: 5)
        r.project = p; p.revisions.append(r); ctx.insert(r)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Revision>()).first
        #expect(fetched?.color == .goldenrod)
        #expect(fetched?.roundNumber == 5)
        #expect(fetched?.colorRaw == "goldenrod")
    }

    @Test func unrecognisedColorRawFallsBackToWhite() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let r = Revision(label: "X", fountainSnapshot: "",
                         authorName: "", sceneCountAtSave: 0, wordCountAtSave: 0)
        r.colorRaw = "vermilion"   // not a real WGA color
        r.project = p; p.revisions.append(r); ctx.insert(r)
        try ctx.save()
        // Forward-compat: typed accessor never crashes, falls back to white.
        #expect(r.color == .white)
    }

    // MARK: - Margin RGB sanity

    @Test func marginRGBValuesAreInRange() {
        for c in RevisionColor.allCases {
            let rgb = c.marginRGB
            for component in [rgb.r, rgb.g, rgb.b] {
                #expect(component >= 0.0 && component <= 1.0,
                        "RGB component out of range for \(c.display): \(component)")
            }
        }
    }

    @Test func marginRGBValuesAreDistinctAcrossFirstCycle() {
        // The first 11 cases (white → ivory) must each have a unique
        // RGB triple — otherwise a writer staring at "blue" pages
        // could mistake them for "pink" pages because they look
        // identical on screen. The "double" series intentionally
        // re-uses the original paper color (Final Draft convention),
        // so we check uniqueness only across the FIRST cycle.
        let firstCycle: [RevisionColor] = [
            .white, .blue, .pink, .yellow, .green,
            .goldenrod, .buff, .salmon, .cherry, .tan, .ivory
        ]
        let triples = Set(firstCycle.map { c in
            "\(c.marginRGB.r)|\(c.marginRGB.g)|\(c.marginRGB.b)"
        })
        #expect(triples.count == firstCycle.count,
                "two colors share an RGB triple — adjust marginRGB")
    }

    @Test func doubleColorsReuseOriginalRGB() {
        // Convention: "Double <Color>" pages are the same paper stock
        // as the original. The qualifier just disambiguates which pass
        // the production is on — the marginRGB must match.
        #expect(RevisionColor.doubleWhite.marginRGB == RevisionColor.white.marginRGB)
        #expect(RevisionColor.doubleBlue.marginRGB == RevisionColor.blue.marginRGB)
        #expect(RevisionColor.doubleCherry.marginRGB == RevisionColor.cherry.marginRGB)
    }

    @Test func marginRGBNonZeroForAllCases() {
        // Every case must have at least one non-zero component (i.e.
        // not pure black) so the stripe is actually visible against
        // the page background.
        for c in RevisionColor.allCases {
            let rgb = c.marginRGB
            #expect(rgb.r > 0 || rgb.g > 0 || rgb.b > 0,
                    "marginRGB is pure black for \(c.display)")
        }
    }
}
