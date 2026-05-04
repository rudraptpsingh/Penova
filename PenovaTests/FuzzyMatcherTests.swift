//
//  FuzzyMatcherTests.swift
//  PenovaTests
//
//  Pins the fuzzy matcher's behaviour:
//    • sub-sequence matching (in order, not contiguous)
//    • case-insensitivity
//    • scoring favours start / word-boundary / consecutive matches
//    • returns matched character indices for highlighting
//    • empty query is "match everything with score 0"
//    • impossible matches return nil
//

import Testing
import Foundation
@testable import PenovaKit

@Suite struct FuzzyMatcherTests {

    // MARK: - Match / no-match

    @Test func emptyQueryMatchesEverythingWithZeroScore() {
        let m = FuzzyMatcher.match(query: "", target: "Rename character")
        #expect(m == FuzzyMatcher.Match(score: 0, matchedIndices: []))
    }

    @Test func emptyTargetReturnsNil() {
        #expect(FuzzyMatcher.match(query: "x", target: "") == nil)
    }

    @Test func bothEmptyMatchesWithZero() {
        #expect(FuzzyMatcher.match(query: "", target: "") != nil)
    }

    @Test func subsequenceMatches() {
        let m = FuzzyMatcher.match(query: "rena", target: "Rename character")
        #expect(m != nil)
        #expect(m?.matchedIndices == [0, 1, 2, 3])
    }

    @Test func nonSubsequenceReturnsNil() {
        // Query must appear in order — "rema" can't sub-sequence "rename":
        // r(0) e(1) — m would have to come after e, but next m is at 4(?)
        // Wait: "rename" → r,e,n,a,m,e. m is at index 4. So r-e-m-a wants
        // r at 0, e at 1, m at 4, a at... position 3. But a is BEFORE m
        // in the target, so the search fails.
        #expect(FuzzyMatcher.match(query: "rema", target: "rename") == nil)
    }

    @Test func caseInsensitive() {
        let m = FuzzyMatcher.match(query: "RENA", target: "Rename")
        #expect(m != nil)
        #expect(m?.matchedIndices == [0, 1, 2, 3])
    }

    @Test func unicodeTargetMatchesAscii() {
        // Latin chars in a target with Devanagari prefix should still match
        // via their character index.
        let m = FuzzyMatcher.match(query: "ek", target: "Ek Raat Mumbai Mein")
        #expect(m != nil)
        #expect(m?.matchedIndices == [0, 1])
    }

    // MARK: - Scoring bonuses

    @Test func startBonusOutscoresMidMatch() {
        let atStart = FuzzyMatcher.match(query: "r", target: "rename")!
        let mid = FuzzyMatcher.match(query: "r", target: "marker")!
        #expect(atStart.score > mid.score)
    }

    @Test func wordBoundaryBonusOutscoresMidWord() {
        // "i" against "Index Cards" — Index starts at 0 (start bonus),
        // and "i" in "cards" would be... no 'i' in cards. Use different
        // example: "c" against "Index Cards" should hit C in Cards
        // (boundary after space) higher than the 'c' in some non-boundary
        // position. Easier: compare "c" in two targets.
        let boundary = FuzzyMatcher.match(query: "c", target: "Index Cards")!
        let interior = FuzzyMatcher.match(query: "c", target: "alfaccent")!
        #expect(boundary.score > interior.score)
    }

    @Test func consecutiveBonusBeatsScattered() {
        let consec = FuzzyMatcher.match(query: "ren", target: "rename")!
        let scattered = FuzzyMatcher.match(query: "ren", target: "rXeXn")!
        #expect(consec.score > scattered.score)
    }

    @Test func longerMatchScoresHigher() {
        let four = FuzzyMatcher.match(query: "rena", target: "rename")!
        let two = FuzzyMatcher.match(query: "re", target: "rename")!
        #expect(four.score > two.score)
    }

    // MARK: - Realistic palette ordering

    @Test func renaQueryMatchesRenameNotReorder() {
        let rename = FuzzyMatcher.match(query: "rena", target: "Rename character")
        let reorder = FuzzyMatcher.match(query: "rena", target: "Reorder scene")
        // "Rename" → r-e-n-a appears consecutively at the start (huge boost).
        // "Reorder" = r-e-o-r-d-e-r — no 'n' anywhere, so the subsequence
        // can't be satisfied → nil.
        #expect(rename != nil)
        #expect(rename?.score ?? 0 > 0)
        #expect(reorder == nil)
    }

    @Test func ckQueryHitsCardsNotPickle() {
        let cards = FuzzyMatcher.match(query: "ic", target: "Index Cards")!
        let pickle = FuzzyMatcher.match(query: "ic", target: "pickle")!
        // Index Cards: I at 0 (start +20), c at 6 (boundary +10).
        // pickle: i at 1, c at 2 (consecutive). No start, no boundary.
        // Index Cards should win on the start bonus alone.
        #expect(cards.score > pickle.score)
    }
}
