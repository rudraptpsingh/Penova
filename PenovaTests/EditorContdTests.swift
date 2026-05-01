//
//  EditorContdTests.swift
//  PenovaTests
//
//  Pins the (CONT'D) auto-insertion contract that v1.1.1 ships:
//  when the same character speaks again in a scene without a different
//  character cue in between, the second cue carries the (CONT'D)
//  marker. Matches Final Draft's "automatic character continueds"
//  default.
//
//  See PenovaKit/EditorLogic.appendContdIfNeeded for the implementation.
//

import Testing
import Foundation
@testable import PenovaKit

@Suite struct EditorContdTests {

    // MARK: - bareCharacterName: strip standard suffixes

    @Test func bareCharacterStripsContd() {
        #expect(EditorLogic.bareCharacterName("JANE (CONT'D)") == "JANE")
    }

    @Test func bareCharacterStripsVO() {
        #expect(EditorLogic.bareCharacterName("JANE (V.O.)") == "JANE")
    }

    @Test func bareCharacterStripsOS() {
        #expect(EditorLogic.bareCharacterName("JANE (O.S.)") == "JANE")
    }

    @Test func bareCharacterStripsMultipleSuffixes() {
        // "JANE (V.O.) (CONT'D)" → "JANE"
        #expect(EditorLogic.bareCharacterName("JANE (V.O.) (CONT'D)") == "JANE")
    }

    @Test func bareCharacterPreservesNonSuffixedName() {
        #expect(EditorLogic.bareCharacterName("JANE") == "JANE")
    }

    @Test func bareCharacterUppercasesInput() {
        #expect(EditorLogic.bareCharacterName("jane (cont'd)") == "JANE")
    }

    // MARK: - appendContdIfNeeded: the core contract

    @Test func consecutiveSameCharacterGetsContd() {
        let result = EditorLogic.appendContdIfNeeded(
            cue: "JANE",
            previousCharacterCue: "JANE"
        )
        #expect(result == "JANE (CONT'D)")
    }

    @Test func consecutiveSameCharacterAcrossSuffixGetsContd() {
        // Previous was "JANE (V.O.)", new is "JANE" — bare name matches,
        // so (CONT'D) appended. (V.O.) suffix stays on the prior cue.
        let result = EditorLogic.appendContdIfNeeded(
            cue: "JANE",
            previousCharacterCue: "JANE (V.O.)"
        )
        #expect(result == "JANE (CONT'D)")
    }

    @Test func newCueWithVOFromContinuedSpeakerKeepsVO() {
        // Writer types "JANE (V.O.)" while the previous cue was
        // a plain "JANE" — they want the VO suffix to remain AND a
        // continuation marker.
        let result = EditorLogic.appendContdIfNeeded(
            cue: "JANE (V.O.)",
            previousCharacterCue: "JANE"
        )
        #expect(result == "JANE (V.O.) (CONT'D)")
    }

    @Test func differentCharacterDoesNotGetContd() {
        let result = EditorLogic.appendContdIfNeeded(
            cue: "BETH",
            previousCharacterCue: "JANE"
        )
        #expect(result == "BETH")
    }

    @Test func firstCharacterInSceneDoesNotGetContd() {
        let result = EditorLogic.appendContdIfNeeded(
            cue: "JANE",
            previousCharacterCue: nil
        )
        #expect(result == "JANE")
    }

    @Test func emptyPreviousCueDoesNotTriggerContd() {
        let result = EditorLogic.appendContdIfNeeded(
            cue: "JANE",
            previousCharacterCue: ""
        )
        #expect(result == "JANE")
    }

    @Test func cueAlreadyContdIsLeftAlone() {
        // Writer typed (CONT'D) themselves — don't double up.
        let result = EditorLogic.appendContdIfNeeded(
            cue: "JANE (CONT'D)",
            previousCharacterCue: "JANE"
        )
        #expect(result == "JANE (CONT'D)")
    }

    @Test func emptyCueIsLeftAlone() {
        let result = EditorLogic.appendContdIfNeeded(
            cue: "",
            previousCharacterCue: "JANE"
        )
        #expect(result == "")
    }

    @Test func whitespaceOnlyCueIsTrimmedToEmpty() {
        let result = EditorLogic.appendContdIfNeeded(
            cue: "   ",
            previousCharacterCue: "JANE"
        )
        #expect(result == "   " || result.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}
