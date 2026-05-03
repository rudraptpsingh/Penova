//
//  FuzzyMatcher.swift
//  PenovaKit
//
//  Sub-sequence fuzzy matcher for the command palette and any other
//  "type a few letters, get a result" surface. The flavour is
//  Sublime / VS Code: every query character must appear in the target
//  in order, but not necessarily contiguously.
//
//  Scoring favours matches that feel right to a writer at the keyboard:
//
//   • Match at index 0          → +20  (the "I started typing the word"
//                                       bonus that makes "rena" beat
//                                       every other partial in the list)
//   • Match after a word        → +10  ("ick" hits "Index Cards" on the
//     boundary (space/-/_/./)         I in "Cards", not the i in "Edit")
//   • Match consecutive to       → +5   ("rena" → "Rename" gets four +5
//     previous match                    bonuses; "rxxxxa" gets none)
//   • Each match                 → +1   (baseline so longer matches sort
//                                       above shorter ones, all else
//                                       equal)
//
//  Pure logic. Zero platform deps. Returns the matched character
//  indices in the target so callers can underline / bold the matched
//  spans in the UI.
//

import Foundation

public enum FuzzyMatcher {

    public struct Match: Equatable, Hashable, Sendable {
        public let score: Int
        /// Character indices in the target string (NOT byte offsets;
        /// suitable for `String.Index` reconstruction via `index(_:offsetBy:)`).
        public let matchedIndices: [Int]

        public init(score: Int, matchedIndices: [Int]) {
            self.score = score
            self.matchedIndices = matchedIndices
        }
    }

    /// Greedy left-to-right match. Returns nil if any query character
    /// has no later occurrence in the target.
    ///
    /// Empty query matches everything with score 0 and no indices —
    /// callers (the palette) typically render the full command list
    /// in this case, sorted by their own static order.
    public static func match(query: String, target: String) -> Match? {
        if query.isEmpty {
            return Match(score: 0, matchedIndices: [])
        }

        let q = Array(query.lowercased())
        let t = Array(target.lowercased())
        guard !t.isEmpty else { return nil }

        var qi = 0
        var indices: [Int] = []
        indices.reserveCapacity(q.count)
        var score = 0
        var prevMatchedIdx = -2 // -2 (not -1) so prevMatchedIdx + 1 != 0 at start

        for ti in 0..<t.count {
            guard qi < q.count else { break }
            if t[ti] == q[qi] {
                indices.append(ti)
                score += 1
                if ti == 0 {
                    score += 20
                } else if Self.isBoundary(t[ti - 1]) {
                    score += 10
                }
                if prevMatchedIdx == ti - 1 {
                    score += 5
                }
                qi += 1
                prevMatchedIdx = ti
            }
        }

        guard qi == q.count else { return nil }
        return Match(score: score, matchedIndices: indices)
    }

    private static let boundaryChars: Set<Character> = [
        " ", "-", "_", "/", ".", ",", ":", ";", "·", "—", "·"
    ]

    @inline(__always)
    private static func isBoundary(_ c: Character) -> Bool {
        boundaryChars.contains(c)
    }
}
