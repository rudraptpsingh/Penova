//
//  ScreenplayPasteConverterTests.swift
//  PenovaTests
//
//  F4 — exercises ScreenplayPasteConverter.convert. Confirms that:
//
//    • Fountain inputs flow through FountainParser and produce typed
//      blocks with character names linked.
//    • Word-shaped paste produces heading + cue + dialogue triples.
//    • Pure prose collapses to a single Action block.
//    • Empty paste returns no blocks (no crash).
//

import Testing
import Foundation
@testable import PenovaKit

@Suite struct ScreenplayPasteConverterTests {

    @Test func emptyInputReturnsNoBlocks() {
        #expect(ScreenplayPasteConverter.convert("").isEmpty)
        #expect(ScreenplayPasteConverter.convert("   \n  \n").isEmpty)
    }

    @Test func plainProseProducesSingleActionBlock() {
        let text = """
        She walked into the kitchen and made coffee.
        It was already too late to start over.
        """
        let blocks = ScreenplayPasteConverter.convert(text)
        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == .action)
        #expect(blocks.first?.text.contains("She walked into the kitchen") == true)
    }

    @Test func wordShapedYieldsThreeTypedElements() {
        // Verdict will be .maybeScreenplay; converter takes the lite path.
        let text = """
        INT. KITCHEN - DAY

        MARY
        Morning.
        """
        let blocks = ScreenplayPasteConverter.convert(text)
        // Expect: heading, character, dialogue
        #expect(blocks.count == 3)
        #expect(blocks[0].kind == .heading)
        #expect(blocks[0].text == "INT. KITCHEN - DAY")
        #expect(blocks[1].kind == .character)
        #expect(blocks[1].text == "MARY")
        #expect(blocks[2].kind == .dialogue)
        #expect(blocks[2].text == "Morning.")
        #expect(blocks[2].characterName == "MARY")
    }

    @Test func cuePlusParentheticalPlusDialogue() {
        let text = """
        INT. KITCHEN - DAY

        MARY
        (whispering)
        Where did you go?
        """
        let blocks = ScreenplayPasteConverter.convert(text)
        // Expect: heading, character, parenthetical, dialogue
        #expect(blocks.count == 4)
        #expect(blocks[0].kind == .heading)
        #expect(blocks[1].kind == .character)
        #expect(blocks[1].text == "MARY")
        #expect(blocks[2].kind == .parenthetical)
        #expect(blocks[2].text == "(whispering)")
        #expect(blocks[2].characterName == "MARY")
        #expect(blocks[3].kind == .dialogue)
        #expect(blocks[3].text == "Where did you go?")
        #expect(blocks[3].characterName == "MARY")
    }

    @Test func fountainTitlePageRoutesThroughFountainParser() {
        // Inputs starting with "Title:" return .fountain — which uses
        // the full FountainParser. The title page itself doesn't
        // produce element blocks (the converter only flattens scenes),
        // but the body should still parse.
        let text = """
        Title: My Movie
        Author: Test

        INT. KITCHEN - DAY

        MARY enters.

        MARY
        Morning.
        """
        let blocks = ScreenplayPasteConverter.convert(text)
        // Expect heading + action + character + dialogue.
        let kinds = blocks.map(\.kind)
        #expect(kinds.contains(.heading))
        #expect(kinds.contains(.character))
        #expect(kinds.contains(.dialogue))
        // Character name should propagate to dialogue.
        let dialogue = blocks.first(where: { $0.kind == .dialogue })
        #expect(dialogue?.characterName == "MARY")
    }
}
