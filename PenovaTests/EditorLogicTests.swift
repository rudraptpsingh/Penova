//
//  EditorLogicTests.swift
//  PenovaTests
//
//  Pure-logic tests for the continuous scene editor. Covers Return key
//  advancement, Tab cycling, commit-time normalisation, character
//  autocomplete matching, and order math.
//

import Testing
import Foundation
import PenovaKit
@testable import Penova

@Suite struct EditorLogicTests {

    // MARK: - nextKind (Return advancement)

    @Test func nextKindHeadingAdvancesToAction() {
        #expect(EditorLogic.nextKind(after: .heading) == .action)
    }

    @Test func nextKindActionAdvancesToAction() {
        #expect(EditorLogic.nextKind(after: .action) == .action)
    }

    @Test func nextKindCharacterAdvancesToDialogue() {
        #expect(EditorLogic.nextKind(after: .character) == .dialogue)
    }

    @Test func nextKindDialogueAdvancesToAction() {
        #expect(EditorLogic.nextKind(after: .dialogue) == .action)
    }

    @Test func nextKindParentheticalAdvancesToDialogue() {
        #expect(EditorLogic.nextKind(after: .parenthetical) == .dialogue)
    }

    @Test func nextKindTransitionAdvancesToHeading() {
        #expect(EditorLogic.nextKind(after: .transition) == .heading)
    }

    // MARK: - tabCycle (hardware Tab / chip cycle)

    @Test func tabCycleHeadingToAction() {
        #expect(EditorLogic.tabCycle(from: .heading) == .action)
    }

    @Test func tabCycleActionToCharacter() {
        #expect(EditorLogic.tabCycle(from: .action) == .character)
    }

    @Test func tabCycleCharacterToDialogue() {
        #expect(EditorLogic.tabCycle(from: .character) == .dialogue)
    }

    @Test func tabCycleDialogueToParenthetical() {
        #expect(EditorLogic.tabCycle(from: .dialogue) == .parenthetical)
    }

    @Test func tabCycleParentheticalToTransition() {
        #expect(EditorLogic.tabCycle(from: .parenthetical) == .transition)
    }

    @Test func tabCycleTransitionGoesToActBreak() {
        #expect(EditorLogic.tabCycle(from: .transition) == .actBreak)
    }

    @Test func tabCycleActBreakWrapsToHeading() {
        #expect(EditorLogic.tabCycle(from: .actBreak) == .heading)
    }

    @Test func tabCycleFullLoopReturnsHome() {
        var k: SceneElementKind = .heading
        for _ in 0..<SceneElementKind.allCases.count {
            k = EditorLogic.tabCycle(from: k)
        }
        #expect(k == .heading)
    }

    // MARK: - normalise

    @Test func normaliseHeadingUppercasesAndTrims() {
        #expect(EditorLogic.normalise(text: "  int. diner - night  ", kind: .heading)
                == "INT. DINER - NIGHT")
    }

    @Test func normaliseCharacterUppercasesAndTrims() {
        #expect(EditorLogic.normalise(text: "  maya  ", kind: .character) == "MAYA")
    }

    @Test func normaliseTransitionUppercases() {
        #expect(EditorLogic.normalise(text: "cut to:", kind: .transition) == "CUT TO:")
    }

    @Test func normaliseParentheticalWrapsBareText() {
        #expect(EditorLogic.normalise(text: "quietly", kind: .parenthetical) == "(quietly)")
    }

    @Test func normaliseParentheticalLeavesWrappedTextAlone() {
        #expect(EditorLogic.normalise(text: "(beat)", kind: .parenthetical) == "(beat)")
    }

    @Test func normaliseEmptyParentheticalStaysEmpty() {
        #expect(EditorLogic.normalise(text: "", kind: .parenthetical) == "")
        #expect(EditorLogic.normalise(text: "   ", kind: .parenthetical) == "")
    }

    @Test func normaliseActionPreservesCase() {
        let s = "Maya walks in, slowly."
        #expect(EditorLogic.normalise(text: s, kind: .action) == s)
    }

    @Test func normaliseDialoguePreservesCase() {
        let s = "I'm not going."
        #expect(EditorLogic.normalise(text: s, kind: .dialogue) == s)
    }

    // MARK: - suggestions (character autocomplete)

    @Test func suggestionsPrefixMatchMA() {
        let out = EditorLogic.suggestions(query: "MA", in: ["MAYA", "MARCUS", "JAMES"])
        #expect(out == ["MAYA", "MARCUS"])
    }

    @Test func suggestionsCaseInsensitive() {
        let out = EditorLogic.suggestions(query: "j", in: ["MAYA", "MARCUS", "JAMES"])
        #expect(out == ["JAMES"])
    }

    @Test func suggestionsEmptyQueryReturnsAll() {
        let names = ["MAYA", "MARCUS", "JAMES"]
        #expect(EditorLogic.suggestions(query: "", in: names) == names)
        #expect(EditorLogic.suggestions(query: "   ", in: names) == names)
    }

    @Test func suggestionsPreservesInputOrder() {
        let names = ["ZARA", "ADAM", "ALICE"]
        let out = EditorLogic.suggestions(query: "A", in: names)
        #expect(out == ["ZARA", "ADAM", "ALICE"])
    }

    @Test func suggestionsNoMatchReturnsEmpty() {
        #expect(EditorLogic.suggestions(query: "Z", in: ["MAYA", "MARCUS"]) == [])
    }

    // MARK: - order math

    @Test func nextOrderAfterNilIsZero() {
        #expect(EditorLogic.nextOrder(after: nil) == 0)
    }

    @Test func nextOrderAfterValueIsPlusOne() {
        #expect(EditorLogic.nextOrder(after: 4) == 5)
    }

    @Test func insertOrderBetweenGapReturnsMidpoint() {
        #expect(EditorLogic.insertOrder(between: 0, and: 10) == 5)
    }

    @Test func insertOrderBetweenAdjacentReturnsNil() {
        #expect(EditorLogic.insertOrder(between: 3, and: 4) == nil)
        #expect(EditorLogic.insertOrder(between: 3, and: 3) == nil)
    }

    @Test func insertOrderBetweenUnordered() {
        // Arguments need not be ordered.
        #expect(EditorLogic.insertOrder(between: 10, and: 0) == 5)
    }

    @Test func compactReturnsSequentialFromZero() {
        #expect(EditorLogic.compact([3, 7, 11]) == [0, 1, 2])
        #expect(EditorLogic.compact([]) == [])
    }
}
