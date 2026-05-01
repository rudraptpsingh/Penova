//
//  PDFScreenplayParserTests.swift
//  PenovaTests
//
//  Mock-driven coverage of PDFScreenplayParser. We don't render real
//  PDFs here — instead we feed a `MockLineSource` that mimics what
//  PDFKit would return after extracting text + bounds from an
//  industry-standard PDF. That isolates the parser's classification,
//  x-clustering, chrome filter, and scene-grouping logic from PDFKit
//  rendering quirks (which are exercised separately in
//  PDFRoundTripImportTests).
//
//  Coordinate system in fixtures: PDF user space, US Letter (612×792),
//  origin lower-left. Industry indents (used widely below):
//    Action / Heading         x = 108  (1.5")
//    Dialogue                 x = 180  (2.5")
//    Parenthetical            x = 223  (3.1")
//    Character cue            x = 266  (3.7")
//    Transition (right-aligned) x = 432  (6.0")
//

import Testing
import Foundation
import CoreGraphics
@testable import Penova
@testable import PenovaKit

// MARK: - Mock line source

private struct MockLineSource: PDFLineSource {
    let pages: [[PDFLine]]
    var pageCount: Int { pages.count }
    func lines(onPage index: Int) -> [PDFLine] { pages[index] }
}

private enum F {
    // Industry indents in points.
    static let action: CGFloat = 108
    static let dialogue: CGFloat = 180
    static let parenthetical: CGFloat = 223
    static let character: CGFloat = 266
    static let transition: CGFloat = 432
    static let pageHeight: CGFloat = 792

    /// Build a line at a given (x, yFromTop) on a US-Letter page.
    static func line(_ text: String, x: CGFloat, yFromTop: CGFloat = 100, page: Int = 0) -> PDFLine {
        PDFLine(text: text, x: x, yTop: pageHeight - yFromTop,
                pageHeight: pageHeight, pageIndex: page)
    }

    /// Convenience: lay out lines top-to-bottom with even spacing.
    static func laidOut(_ items: [(String, CGFloat)], page: Int = 0,
                        startY: CGFloat = 100, spacing: CGFloat = 24) -> [PDFLine] {
        items.enumerated().map { idx, item in
            line(item.0, x: item.1, yFromTop: startY + CGFloat(idx) * spacing, page: page)
        }
    }
}

@Suite struct PDFScreenplayParserTests {

    // MARK: - Classification basics

    @Test func classifiesSceneHeadingByPrefix() {
        let lines = F.laidOut([
            ("INT. KITCHEN - DAY", F.action),
            ("Eggs spit on the stove.", F.action),
        ])
        let result = PDFScreenplayParser.parse(MockLineSource(pages: [lines]))
        #expect(result.document.scenes.count == 1)
        #expect(result.document.scenes.first?.heading == "INT. KITCHEN - DAY")
        #expect(result.document.scenes.first?.elements.first?.kind == .action)
        #expect(result.document.scenes.first?.elements.first?.text == "Eggs spit on the stove.")
    }

    @Test func classifiesEXTAndESTHeadings() {
        let lines = [
            F.line("EXT. STREET - NIGHT",  x: F.action, yFromTop: 100),
            F.line("Action.",              x: F.action, yFromTop: 130),
            F.line("EST. CITY - DAY",      x: F.action, yFromTop: 160),
            F.line("More action.",         x: F.action, yFromTop: 190),
        ]
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [lines]))
        #expect(r.document.scenes.count == 2)
        #expect(r.document.scenes.map(\.heading) == ["EXT. STREET - NIGHT", "EST. CITY - DAY"])
    }

    @Test func classifiesCharacterCueDialogueParenthetical() {
        let lines = F.laidOut([
            ("INT. ROOM - DAY",   F.action),
            ("She turns.",        F.action),
            ("ALICE",             F.character),
            ("(softly)",          F.parenthetical),
            ("Hello, world.",     F.dialogue),
        ])
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [lines]))
        let scene = r.document.scenes.first
        #expect(scene?.elements.map(\.kind) == [.action, .character, .parenthetical, .dialogue])
        #expect(scene?.elements[1].text == "ALICE")
        #expect(scene?.elements[2].text == "(softly)")
        #expect(scene?.elements[3].text == "Hello, world.")
    }

    @Test func mergesMultilineDialogueIntoSingleBlock() {
        let lines = F.laidOut([
            ("INT. ROOM - DAY",                  F.action),
            ("BOB",                              F.character),
            ("Listen carefully — this matters.", F.dialogue),
            ("There won't be another chance.",   F.dialogue),
        ])
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [lines]))
        let scene = r.document.scenes.first
        #expect(scene?.elements.count == 2)        // character + one dialogue
        #expect(scene?.elements.last?.kind == .dialogue)
        #expect(scene?.elements.last?.text == "Listen carefully — this matters. There won't be another chance.")
    }

    @Test func mergesMultilineActionIntoSingleBlock() {
        let lines = F.laidOut([
            ("INT. ROOM - DAY",                  F.action),
            ("She enters slowly.",                F.action),
            ("Her eyes adjust to the dark.",      F.action),
        ])
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [lines]))
        let scene = r.document.scenes.first
        #expect(scene?.elements.count == 1)
        #expect(scene?.elements.first?.text ==
                "She enters slowly. Her eyes adjust to the dark.")
    }

    @Test func classifiesTransitionByPattern() {
        let lines = F.laidOut([
            ("INT. ROOM - DAY",  F.action),
            ("She leaves.",       F.action),
            ("CUT TO:",           F.transition),
            ("INT. STREET - DAY", F.action),
            ("She walks.",        F.action),
            ("FADE OUT.",         F.transition),
        ])
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [lines]))
        #expect(r.document.scenes.count == 2)
        let s1 = r.document.scenes[0]
        #expect(s1.elements.last?.kind == .transition)
        #expect(s1.elements.last?.text == "CUT TO:")
        let s2 = r.document.scenes[1]
        #expect(s2.elements.last?.kind == .transition)
        #expect(s2.elements.last?.text == "FADE OUT.")
    }

    // MARK: - Cue suffix cleanup

    @Test func stripsContDFromCharacterCue() {
        let s = PDFScreenplayParser.stripCueSuffix("ALICE (CONT'D)")
        #expect(s == "ALICE")
    }

    @Test func stripsVOFromCharacterCue() {
        #expect(PDFScreenplayParser.stripCueSuffix("ALICE (V.O.)") == "ALICE")
        #expect(PDFScreenplayParser.stripCueSuffix("ALICE (O.S.)") == "ALICE")
        // No suffix? leave it alone.
        #expect(PDFScreenplayParser.stripCueSuffix("ALICE") == "ALICE")
    }

    @Test func stripsSceneNumberPrefix() {
        #expect(PDFScreenplayParser.stripSceneNumberPrefix("12   INT. KITCHEN - DAY   12") ==
                "INT. KITCHEN - DAY")
        #expect(PDFScreenplayParser.stripSceneNumberPrefix("A12  EXT. STREET - NIGHT  A12") ==
                "EXT. STREET - NIGHT")
        #expect(PDFScreenplayParser.stripSceneNumberPrefix("INT. KITCHEN - DAY") ==
                "INT. KITCHEN - DAY")
    }

    // MARK: - Chrome filtering

    @Test func dropsPageNumbers() {
        // Build two pages: each has a page number near the top.
        let p1 = [
            F.line("1.", x: 540, yFromTop: 30, page: 0),
            F.line("INT. ROOM - DAY", x: F.action, yFromTop: 100, page: 0),
            F.line("She enters.",     x: F.action, yFromTop: 130, page: 0),
        ]
        let p2 = [
            F.line("2.", x: 540, yFromTop: 30, page: 1),
            F.line("She leaves.",     x: F.action, yFromTop: 100, page: 1),
        ]
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [p1, p2]))
        let scene = r.document.scenes.first
        #expect(r.document.scenes.count == 1)
        // The "1." and "2." page numbers must NOT have been promoted to
        // headings or actions.
        #expect(scene?.elements.contains(where: { $0.text.contains("1.") || $0.text.contains("2.") }) == false)
        #expect(r.diagnostics.droppedChromeCount >= 2)
    }

    @Test func dropsMOREAndCONTINUEDMarkers() {
        let lines = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("BOB",             F.character),
            ("First line.",     F.dialogue),
            ("(MORE)",          F.character),     // bottom of page chrome
            ("(CONTINUED)",     F.action),        // any column
        ])
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [lines]))
        let scene = r.document.scenes.first
        #expect(scene?.elements.contains(where: { $0.text.uppercased().contains("MORE") }) == false)
        #expect(scene?.elements.contains(where: { $0.text.uppercased().contains("CONTINUED") }) == false)
    }

    // MARK: - X-clustering

    @Test func inferColumnsFindsFiveBucketsWhenAllPresent() {
        let lines = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("Action 1.",       F.action),
            ("Action 2.",       F.action),
            ("BOB",             F.character),
            ("ALICE",           F.character),
            ("(softly)",        F.parenthetical),
            ("(loudly)",        F.parenthetical),
            ("Hello.",          F.dialogue),
            ("World.",          F.dialogue),
            ("CUT TO:",         F.transition),
            ("FADE OUT.",       F.transition),
        ])
        let cols = PDFScreenplayParser.inferColumns(lines)
        #expect(cols.action != nil)
        #expect(cols.dialogue != nil)
        #expect(cols.parenthetical != nil)
        #expect(cols.character != nil)
        #expect(cols.transition != nil)
        // Ordering invariant.
        let sorted = [cols.action, cols.dialogue, cols.parenthetical, cols.character, cols.transition]
            .compactMap { $0 }
        #expect(sorted == sorted.sorted())
    }

    @Test func inferColumnsHandlesTwoBucketScript() {
        // A document with only action + dialogue (no parenthetical, no
        // character cues — extreme edge case).
        let lines = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("Action 1.",       F.action),
            ("Action 2.",       F.action),
            ("Hello.",          F.dialogue),
            ("World.",          F.dialogue),
        ])
        let cols = PDFScreenplayParser.inferColumns(lines)
        #expect(cols.action != nil)
        #expect(cols.dialogue != nil)
        #expect(cols.parenthetical == nil)
    }

    @Test func inferColumnsIgnoresOutliers() {
        // Single stray line at an unusual indent should not become a
        // phantom column (we require ≥ 2 hits per bucket).
        var lines = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("Action 1.",       F.action),
            ("Action 2.",       F.action),
            ("Hello.",          F.dialogue),
            ("World.",          F.dialogue),
        ])
        lines.append(F.line("OUTLIER", x: 350, yFromTop: 400))
        let cols = PDFScreenplayParser.inferColumns(lines)
        #expect(cols.action != nil)
        #expect(cols.dialogue != nil)
        #expect(cols.character == nil)         // 350 was a one-off
        #expect(cols.parenthetical == nil)
    }

    // MARK: - Title page

    @Test func parsesKeyValueTitlePage() {
        let p0 = F.laidOut([
            ("Title: Ek Raat Mumbai Mein", 200),
            ("Author: P. K. Iyer",         200),
        ])
        let p1 = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("She enters.",     F.action),
        ], page: 1)
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [p0, p1]))
        #expect(r.diagnostics.hadTitlePage == true)
        #expect(r.document.titlePage["title"] == "Ek Raat Mumbai Mein")
        #expect(r.document.titlePage["author"] == "P. K. Iyer")
        #expect(r.document.scenes.count == 1)
    }

    @Test func parsesCenteredTitleByConvention() {
        let p0 = [
            F.line("THE LAST TRAIN",   x: 240, yFromTop: 250, page: 0),
            F.line("by Jane Author",   x: 240, yFromTop: 290, page: 0),
        ]
        let p1 = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("Action.",         F.action),
        ], page: 1)
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [p0, p1]))
        #expect(r.diagnostics.hadTitlePage == true)
        #expect(r.document.titlePage["title"] == "THE LAST TRAIN")
        #expect(r.document.titlePage["author"] == "Jane Author")
    }

    @Test func skipsTitlePageDetectionWhenPage0HasSceneHeading() {
        // No title page — the script opens with a scene on page 0.
        let p0 = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("Action.",         F.action),
        ])
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [p0]))
        #expect(r.diagnostics.hadTitlePage == false)
        #expect(r.document.scenes.count == 1)
    }

    // MARK: - Robustness

    @Test func emptyDocumentReturnsEmptyParse() {
        let r = PDFScreenplayParser.parse(MockLineSource(pages: []))
        #expect(r.document.scenes.isEmpty)
        #expect(r.diagnostics.pageCount == 0)
    }

    @Test func multipleScenesAcrossPagesAreCounted() {
        let p0 = F.laidOut([
            ("INT. ROOM - DAY",   F.action),
            ("BOB",                F.character),
            ("Hello.",             F.dialogue),
        ])
        let p1 = F.laidOut([
            ("INT. STREET - DAY", F.action),
            ("She walks.",         F.action),
        ], page: 1)
        let p2 = F.laidOut([
            ("EXT. PARK - NIGHT", F.action),
            ("Wind rustles.",     F.action),
        ], page: 2)
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [p0, p1, p2]))
        #expect(r.document.scenes.count == 3)
        #expect(r.diagnostics.pageCount == 3)
        #expect(r.diagnostics.sceneCount == 3)
    }

    // MARK: - Scene heading text helper

    @Test func sceneHeadingDetectorRecognizesAllStandardPrefixes() {
        let prefixes = ["INT.", "EXT.", "EST.", "INT/EXT.", "I/E."]
        for p in prefixes {
            let l = F.line("\(p) ROOM - DAY", x: F.action)
            #expect(PDFScreenplayParser.isSceneHeadingText(l), "missed prefix \(p)")
        }
    }

    @Test func sceneHeadingDetectorIgnoresNarrativeProse() {
        let l = F.line("Inside, the cat blinks.", x: F.action)
        #expect(PDFScreenplayParser.isSceneHeadingText(l) == false)
    }

    // MARK: - All-caps fallback

    @Test func wonkyTemplateFallsBackToContentClassification() {
        // No clean column structure — every line at the same x. The
        // parser should still pick up scene headings (by prefix) and
        // ALL CAPS short lines as character cues (by content).
        let lines = F.laidOut([
            ("INT. WAREHOUSE - NIGHT", 130),
            ("BOB",                    130),
            ("This is a problem.",     130),
            ("ALICE",                  130),
            ("Indeed it is.",          130),
        ])
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [lines]))
        let kinds = r.document.scenes.first?.elements.map(\.kind) ?? []
        // Two character cues and two dialogue blocks should be detected
        // even though x-clustering produced only one bucket.
        #expect(kinds.filter { $0 == .character }.count == 2)
    }

    // MARK: - Cue-suffix normalisation in the parsed output

    @Test func contdSuffixInCharacterCueIsStrippedDuringParse() {
        let lines = F.laidOut([
            ("INT. ROOM - DAY",      F.action),
            ("ALICE (CONT'D)",        F.character),
            ("I said it twice.",     F.dialogue),
        ])
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [lines]))
        let cue = r.document.scenes.first?.elements.first { $0.kind == .character }
        #expect(cue?.text == "ALICE")
    }

    // MARK: - Stacked cue suffixes (regression: real Hollywood scripts)

    @Test func stripsStackedCueSuffixes() {
        // RAVI (V.O.) (CONT'D) — common after a page break in
        // continuous V.O. dialogue. Both suffixes must come off.
        #expect(PDFScreenplayParser.stripCueSuffix("RAVI (V.O.) (CONT'D)") == "RAVI")
        #expect(PDFScreenplayParser.stripCueSuffix("ALICE (O.S.) (CONT'D)") == "ALICE")
        #expect(PDFScreenplayParser.stripCueSuffix("BOB (CONT'D)") == "BOB")
        #expect(PDFScreenplayParser.stripCueSuffix("BOB") == "BOB")
    }

    // MARK: - Same-y line merging (regression: pdftotext / Big Fish)

    @Test func mergeSameYLinesGluesSplitSceneHeading() {
        // PDF text extractors sometimes split "INT. WILL'S BEDROOM"
        // into two lines at the period. The merge pass glues them
        // back together when their y-tops are within tolerance.
        let split = [
            PDFLine(text: "INT.",                          x: 108, yTop: 700, pageHeight: 792, pageIndex: 0),
            PDFLine(text: "WILL'S BEDROOM - NIGHT (1973)", x: 150, yTop: 700, pageHeight: 792, pageIndex: 0),
            PDFLine(text: "Action below.",                 x: 108, yTop: 670, pageHeight: 792, pageIndex: 0),
        ]
        let merged = PDFScreenplayParser.mergeSameYLines(split)
        #expect(merged.count == 2)
        #expect(merged.first?.text == "INT. WILL'S BEDROOM - NIGHT (1973)")
        #expect(merged.first?.x == 108)
    }

    @Test func mergeSameYLinesLeavesDifferentYsAlone() {
        let stacked = [
            PDFLine(text: "Top",    x: 108, yTop: 700, pageHeight: 792, pageIndex: 0),
            PDFLine(text: "Middle", x: 108, yTop: 670, pageHeight: 792, pageIndex: 0),
            PDFLine(text: "Bottom", x: 108, yTop: 640, pageHeight: 792, pageIndex: 0),
        ]
        let merged = PDFScreenplayParser.mergeSameYLines(stacked)
        #expect(merged.count == 3)
        #expect(merged.map(\.text) == ["Top", "Middle", "Bottom"])
    }

    // MARK: - Column validation (regression: Big Fish parenthetical mislabel)

    @Test func validateColumnsDemotesFakeParenthetical() {
        // Build a sample where the inferred "parenthetical" column has
        // mostly real dialogue text, not paren-wrapped lines. The
        // validator should demote it and (because it has more lines)
        // promote it to be the dialogue column.
        var samples: [PDFLine] = []
        // 20 dialogue lines at the "parenthetical" column (174).
        for i in 0..<20 {
            samples.append(F.line("Dialogue line \(i).", x: 174, yFromTop: CGFloat(100 + i * 14)))
        }
        // 5 lines at the originally-labelled dialogue column (150).
        for i in 0..<5 {
            samples.append(F.line("Other \(i).", x: 150, yFromTop: CGFloat(400 + i * 14)))
        }
        // No real parentheticals at 174 — only one decoy line.
        samples.append(F.line("(decoy)", x: 174, yFromTop: 600))

        let initial = PDFScreenplayParser.Columns(
            action: 108, character: nil, parenthetical: 174,
            dialogue: 150, transition: nil
        )
        let validated = PDFScreenplayParser.validateColumns(initial, against: samples)
        #expect(validated.parenthetical == nil)
        // The 174 column had 21 lines vs 5 at 150, so it WAS the real
        // dialogue and should have been promoted.
        #expect(validated.dialogue == 174)
    }

    @Test func validateColumnsKeepsRealParenthetical() {
        // The "parenthetical" column genuinely contains parens-wrapped
        // text — should not be demoted.
        var samples: [PDFLine] = []
        for i in 0..<10 {
            samples.append(F.line("(beat)",  x: 223, yFromTop: CGFloat(100 + i * 14)))
        }
        for i in 0..<10 {
            samples.append(F.line("Dialogue \(i).", x: 180, yFromTop: CGFloat(300 + i * 14)))
        }
        let initial = PDFScreenplayParser.Columns(
            action: 108, character: nil, parenthetical: 223,
            dialogue: 180, transition: nil
        )
        let validated = PDFScreenplayParser.validateColumns(initial, against: samples)
        #expect(validated.parenthetical == 223)
        #expect(validated.dialogue == 180)
    }

    @Test func validateColumnsDemotesFakeCharacterColumn() {
        // The "character" column has mostly long lowercase prose — it
        // isn't really character cues. Demote it.
        var samples: [PDFLine] = []
        for i in 0..<10 {
            samples.append(F.line(
                "the quick brown fox jumps \(i)", x: 266, yFromTop: CGFloat(100 + i * 14)
            ))
        }
        let initial = PDFScreenplayParser.Columns(
            action: 108, character: 266, parenthetical: nil,
            dialogue: 180, transition: nil
        )
        let validated = PDFScreenplayParser.validateColumns(initial, against: samples)
        #expect(validated.character == nil)
    }

    // MARK: - Standalone-author label (regression: Brick & Steel / Big Fish)

    @Test func standaloneWrittenByLabelGrabsNextLine() {
        // Title page rendered as three centered lines:
        //   TITLE
        //   written by
        //   John August
        // "written by" alone shouldn't BECOME the author — the next
        // line should.
        let p0 = [
            F.line("BIG FISH",      x: 240, yFromTop: 200, page: 0),
            F.line("written by",    x: 240, yFromTop: 240, page: 0),
            F.line("John August",   x: 240, yFromTop: 280, page: 0),
        ]
        let p1 = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("Action.",         F.action),
        ], page: 1)
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [p0, p1]))
        #expect(r.diagnostics.hadTitlePage)
        #expect(r.document.titlePage["title"] == "BIG FISH")
        #expect(r.document.titlePage["author"] == "John August")
    }

    @Test func standaloneByLabelGrabsNextLine() {
        let p0 = [
            F.line("THE LAST TRAIN", x: 240, yFromTop: 200, page: 0),
            F.line("by",             x: 240, yFromTop: 240, page: 0),
            F.line("Penova Test",    x: 240, yFromTop: 280, page: 0),
        ]
        let p1 = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("Action.",         F.action),
        ], page: 1)
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [p0, p1]))
        #expect(r.document.titlePage["author"] == "Penova Test")
    }

    @Test func inlineByPrefixStillWorks() {
        let p0 = [
            F.line("THE LAST TRAIN",         x: 240, yFromTop: 200, page: 0),
            F.line("by Penova Test",         x: 240, yFromTop: 240, page: 0),
        ]
        let p1 = F.laidOut([
            ("INT. ROOM - DAY", F.action),
            ("Action.",         F.action),
        ], page: 1)
        let r = PDFScreenplayParser.parse(MockLineSource(pages: [p0, p1]))
        #expect(r.document.titlePage["author"] == "Penova Test")
    }
}
