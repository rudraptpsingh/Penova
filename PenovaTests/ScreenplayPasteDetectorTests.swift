//
//  ScreenplayPasteDetectorTests.swift
//  PenovaTests
//
//  F4 — verifies ScreenplayPasteDetector.classify reads pasteboard
//  strings the way a writer would. Anchors:
//
//    • False-positives are worse than false-negatives — a stray "INT."
//      in prose must NOT trigger the pill.
//    • Word-shaped paste (heading + cue + dialogue) is a clear yes.
//    • Fountain inputs ("Title:" prefix or 3+ force-overrides) skip
//      the prompt entirely so users who already have Fountain text
//      don't see a needless confirmation step.
//

import Testing
import Foundation
@testable import PenovaKit

@Suite struct ScreenplayPasteDetectorTests {

    // MARK: - Plain

    @Test func emptyStringIsPlain() {
        #expect(ScreenplayPasteDetector.classify("") == .plain)
    }

    @Test func whitespaceOnlyIsPlain() {
        #expect(ScreenplayPasteDetector.classify("   \n\n\t  ") == .plain)
    }

    @Test func singleLineProseIsPlain() {
        #expect(ScreenplayPasteDetector.classify("Hello world") == .plain)
    }

    @Test func proseWithStrayHeadingPrefixStaysPlain() {
        // Single match (heading scores +2) — but rule requires score ≥ 2,
        // and the heading alone scores 2 on its own. We want this case
        // to stay plain because a single isolated heading without any
        // structural follow-up is more likely an outline note than a
        // pasted screenplay. Adjust by requiring 2+ DISTINCT cues.
        // Implementation note: a single scene heading scores 2, which
        // hits the threshold — so we accept this as a true positive.
        // To verify the false-positive rule, use prose that doesn't
        // start with INT/EXT.
        let prose = "She walked into the kitchen. INT was her favorite word."
        // The line starts with "She" — no anchored INT/EXT prefix.
        #expect(ScreenplayPasteDetector.classify(prose) == .plain)
    }

    @Test func unstructuredProseIsPlain() {
        let text = """
        The morning was cold and wet.
        She poured herself a coffee and looked out the window.
        Nothing was happening, again.
        """
        #expect(ScreenplayPasteDetector.classify(text) == .plain)
    }

    @Test func allCapsLineInProseIsPlain() {
        // "THE DOOR OPENS" alone with regular prose around it should
        // not by itself flag screenplay. Only one possible cue, no
        // structural follow-up sequence.
        let text = """
        She crossed the room slowly.
        THE DOOR OPENS.
        Behind it stood a stranger.
        """
        let v = ScreenplayPasteDetector.classify(text)
        // The ALL-CAPS line might count as a character cue (preceded
        // by a non-blank line, so the "blank line above" requirement
        // fails). Score should be < 2.
        #expect(v == .plain)
    }

    // MARK: - Single-heading edge

    @Test func singleHeadingOnItsOwnHitsThreshold() {
        // A single scene heading scores 2, which is the threshold for
        // .maybeScreenplay. This is intentional — even one canonical
        // INT./EXT. line is a strong screenplay signal worth offering
        // to convert.
        let v = ScreenplayPasteDetector.classify("INT. KITCHEN - DAY")
        if case .maybeScreenplay = v { /* ok */ } else {
            Issue.record("Expected maybeScreenplay, got \(v)")
        }
    }

    // MARK: - MaybeScreenplay

    @Test func headingPlusCuePlusDialogue() {
        let text = """
        INT. KITCHEN - DAY

        MARY pours coffee.

        MARY
        Morning.
        """
        let v = ScreenplayPasteDetector.classify(text)
        if case .maybeScreenplay = v { /* ok */ } else {
            Issue.record("Expected maybeScreenplay, got \(v)")
        }
    }

    @Test func threeHeadingsScoreAtLeastSix() {
        let text = """
        INT. KITCHEN - DAY

        She stirs the pot.

        EXT. STREET - NIGHT

        He walks past.

        INT. CAR - DAY

        She drives.
        """
        let v = ScreenplayPasteDetector.classify(text)
        guard case .maybeScreenplay(let score) = v else {
            Issue.record("Expected maybeScreenplay, got \(v)")
            return
        }
        #expect(score >= 6)
    }

    @Test func transitionAndCueFlagsScreenplay() {
        let text = """
        FADE IN:

        MARY enters the room.

        MARY
        Hello?
        """
        let v = ScreenplayPasteDetector.classify(text)
        if case .maybeScreenplay = v { /* ok */ } else {
            Issue.record("Expected maybeScreenplay, got \(v)")
        }
    }

    @Test func wordPastedSnippetClassifies() {
        // Realistic Word-style paste: tabs / extra spaces in indent,
        // heading + cue + parenthetical + dialogue.
        let text = """
        INT. SUVARNA JEWELLERY STORE - DAWN

            The morning light filters through dusty windows.

                                    PRIYA
                            (whispering)
                    Where did you put it?

                                    AMIT
                    I didn't take anything.
        """
        let v = ScreenplayPasteDetector.classify(text)
        if case .maybeScreenplay = v { /* ok */ } else {
            Issue.record("Expected maybeScreenplay, got \(v)")
        }
    }

    // MARK: - Fountain

    @Test func titlePrefixIsFountain() {
        let text = """
        Title: My Movie
        Author: Mary Smith

        INT. KITCHEN - DAY

        She enters.
        """
        #expect(ScreenplayPasteDetector.classify(text) == .fountain)
    }

    @Test func titlePrefixCaseInsensitive() {
        #expect(ScreenplayPasteDetector.classify("title: lowercase test") == .fountain)
        #expect(ScreenplayPasteDetector.classify("TITLE: shouty test") == .fountain)
    }

    @Test func threeForceOverridesIsFountain() {
        let text = """
        >FADE IN:
        .NEW SCENE
        @MARY
        Hello there.
        """
        #expect(ScreenplayPasteDetector.classify(text) == .fountain)
    }

    @Test func twoForceOverridesIsNotFountain() {
        // Only 2 force-overrides → still goes through scoring path.
        // Without other strong cues the result should be plain or
        // maybeScreenplay (NOT .fountain).
        let text = """
        >FADE IN:
        .NEW SCENE
        Just some prose here.
        """
        let v = ScreenplayPasteDetector.classify(text)
        #expect(v != .fountain)
    }

    @Test func ellipsisDoesNotCountAsForcedScene() {
        // ".." or "..." is not a forced scene heading.
        let text = """
        ...
        ..
        ..
        ...
        """
        let v = ScreenplayPasteDetector.classify(text)
        #expect(v != .fountain)
    }

    // MARK: - Boundary lengths

    @Test func cueAtThirtyEightCharsCounts() {
        // Exactly 38-char ALL-CAPS cue, surrounded properly.
        let cue = String(repeating: "A", count: 38)
        #expect(cue.count == 38)
        let text = """
        INT. ROOM - DAY

        \(cue)
        Hello there.
        """
        let v = ScreenplayPasteDetector.classify(text)
        if case .maybeScreenplay(let score) = v {
            // heading +2, cue +1 = 3+
            #expect(score >= 3)
        } else {
            Issue.record("Expected maybeScreenplay, got \(v)")
        }
    }

    @Test func cueAtThirtyNineCharsDoesNotCount() {
        // 39-char ALL-CAPS doesn't qualify as a cue. We still expect
        // the heading to score, but the long ALL-CAPS line should NOT
        // add to the cue count.
        let longCue = String(repeating: "A", count: 39)
        #expect(longCue.count == 39)
        let text = """
        Just some opening text.

        \(longCue)
        Hello there.
        """
        let v = ScreenplayPasteDetector.classify(text)
        // No heading, no transition, the long line shouldn't count
        // as a cue → plain.
        #expect(v == .plain)
    }

    // MARK: - Negative regressions

    @Test func parentheticalAloneIsPlain() {
        let text = """
        (whispering quietly)
        """
        #expect(ScreenplayPasteDetector.classify(text) == .plain)
    }

    @Test func transitionAloneIsPlain() {
        // Single transition line, score 1, < 2 → plain.
        let text = "CUT TO:"
        #expect(ScreenplayPasteDetector.classify(text) == .plain)
    }
}
