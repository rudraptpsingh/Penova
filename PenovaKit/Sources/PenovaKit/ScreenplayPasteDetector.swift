//
//  ScreenplayPasteDetector.swift
//  PenovaKit
//
//  F4 — Smart paste detection. Pure-function utility that classifies a
//  pasteboard string as either:
//
//    • `.fountain`        — has explicit Fountain markers (title page or
//                            3+ force-overrides). Skip the prompt and
//                            parse directly through FountainParser.
//    • `.maybeScreenplay` — looks structurally like a screenplay (2+
//                            scoring matches in the first 20 lines).
//                            Show an inline pill at the cursor offering
//                            "Convert" / "Keep as plain text".
//    • `.plain`           — doesn't look like a screenplay. Paste as a
//                            single Action element.
//
//  This is detection only — the actual conversion lives in
//  `ScreenplayPasteConverter`. The detector is intentionally
//  conservative: false-positives are worse than false-negatives because
//  they put a pill in the writer's face for normal prose.
//

import Foundation

public enum ScreenplayPasteVerdict: Equatable, Sendable {
    /// Definitely Fountain — skip the prompt, parse directly.
    case fountain
    /// Likely a screenplay. Show the prompt; let the user decide.
    case maybeScreenplay(score: Int)
    /// Doesn't look like a screenplay. Paste as plain Action.
    case plain
}

public enum ScreenplayPasteDetector {

    /// Classify a pasteboard string. Score each rule once; sum decides
    /// the verdict. See file header for rule definitions.
    public static func classify(_ text: String) -> ScreenplayPasteVerdict {
        // Normalise line endings + split.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let allLines = normalized.components(separatedBy: "\n")

        // Empty / whitespace-only paste → plain.
        if allLines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return .plain
        }

        // Fountain title page: first non-blank line begins with "Title:"
        // (case-insensitive). The Fountain spec actually wants Title to
        // be at the very top, so we check the first non-blank line
        // rather than scanning the whole document.
        if let firstNonBlank = allLines.first(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) {
            let lower = firstNonBlank.lowercased()
            if lower.hasPrefix("title:") {
                return .fountain
            }
        }

        // Force-override count over the first 30 lines. Fountain treats
        // a leading `>`, `.`, `@`, or `!` (when not part of regular
        // punctuation) as a structural override. 3+ in 30 lines is a
        // very strong "this is Fountain" signal.
        let head30 = Array(allLines.prefix(30))
        var forceCount = 0
        for line in head30 {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let first = t.first else { continue }
            // `.` alone isn't enough — `..` or three dots is an
            // ellipsis, not a forced scene. The Fountain spec says
            // a forced scene heading is a single leading dot followed
            // by a non-dot.
            if first == "." {
                if t.count >= 2 && t[t.index(after: t.startIndex)] != "." {
                    forceCount += 1
                }
                continue
            }
            // `!` forces an action line; `@` forces a character cue;
            // `>` forces a transition (or centred text with a trailing
            // `<`). All require at least one character of content
            // after the marker so `> ` alone isn't counted.
            if first == "!" || first == "@" || first == ">" {
                if t.count >= 2 { forceCount += 1 }
            }
        }
        if forceCount >= 3 {
            return .fountain
        }

        // Scoring sweep over the first 20 lines.
        let head20 = Array(allLines.prefix(20))
        var score = 0

        for (i, line) in head20.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Scene heading: anchored INT/EXT/EST + content. Strong signal.
            if isSceneHeading(trimmed) {
                score += 2
                continue
            }

            // Transition: ALL-CAPS ending in `:`, or starts with FADE /
            // CUT TO / SMASH CUT / DISSOLVE.
            if isTransition(trimmed) {
                score += 1
                continue
            }

            // Parenthetical: line wrapped in ( ), sits between a
            // character cue and a dialogue line.
            if isParenthetical(trimmed) {
                let prevNonBlank = previousNonBlank(in: head20, before: i)
                let nextNonBlank = nextNonBlank(in: head20, after: i)
                if let prev = prevNonBlank, isCharacterCueShape(prev),
                   let next = nextNonBlank, !isCharacterCueShape(next),
                   !isParenthetical(next) {
                    score += 1
                }
                continue
            }

            // Character cue: ALL-CAPS line, length 1–38, preceded by a
            // blank line, followed by an indented or non-blank text line.
            if isCharacterCueShape(trimmed) {
                let prevIsBlank = i == 0 || head20[i - 1]
                    .trimmingCharacters(in: .whitespaces).isEmpty
                let nextLine = i + 1 < head20.count ? head20[i + 1] : nil
                let nextNonBlank = nextLine
                    .map { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    ?? false
                if prevIsBlank && nextNonBlank {
                    // Don't double-count if it also looks like a transition.
                    if !isTransition(trimmed) {
                        score += 1
                    }
                }
                continue
            }
        }

        if score >= 2 {
            return .maybeScreenplay(score: score)
        }
        return .plain
    }

    // MARK: - Shape predicates (also used by the converter)

    /// Anchored scene heading: line begins with INT/EXT/EST/INT.EXT
    /// optionally followed by a dot, then whitespace, then content.
    static func isSceneHeading(_ line: String) -> Bool {
        let upper = line.uppercased()
        // Match the prefixes the existing FountainParser knows.
        let prefixes = [
            "INT./EXT.", "INT/EXT.", "INT./EXT", "INT/EXT",
            "I./E.", "I/E.", "I/E ", "I./E ",
            "INT.", "EXT.", "EST.",
            "INT ", "EXT ", "EST "
        ]
        guard prefixes.contains(where: { upper.hasPrefix($0) }) else {
            return false
        }
        // Must have at least one non-space character after the prefix
        // (i.e. a location).
        let trimmed = upper.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 6
    }

    /// Transition: ALL-CAPS ending in `:`, or one of the canonical
    /// FADE/CUT/SMASH/DISSOLVE prefixes (case-insensitive on the
    /// keyword check, but the line itself must still be ALL-CAPS).
    static func isTransition(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        // Avoid flagging plain headings / character cues that happen
        // to end in a colon ("MEANWHILE:" etc. — too ambiguous).
        let upper = trimmed.uppercased()
        guard upper == trimmed else { return false }   // must be all caps
        if upper.hasSuffix("TO:") { return true }
        if upper == "FADE OUT." || upper == "FADE OUT:" { return true }
        if upper.hasPrefix("FADE IN") { return true }
        if upper.hasPrefix("FADE OUT") { return true }
        if upper.hasPrefix("CUT TO") { return true }
        if upper.hasPrefix("SMASH CUT") { return true }
        if upper.hasPrefix("DISSOLVE") { return true }
        return false
    }

    static func isParenthetical(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("(") && t.hasSuffix(")") && t.count >= 2
    }

    /// "Looks like a character cue" — ALL-CAPS, 1–38 chars (Fountain
    /// caps cue length around there; Final Draft uses 38 too), with at
    /// least one letter. Doesn't check surrounding context — callers
    /// layer that on top.
    static func isCharacterCueShape(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 38 else { return false }
        // Must contain at least one letter.
        guard t.rangeOfCharacter(from: .letters) != nil else { return false }
        // Letters must all be upper-case. Digits/punctuation tolerated
        // (e.g. "MARY (V.O.)", "AGENT 47").
        let letters = t.filter { $0.isLetter }
        guard letters == letters.uppercased() else { return false }
        // Don't flag scene headings.
        if isSceneHeading(t) { return false }
        return true
    }

    // MARK: - Helpers

    private static func previousNonBlank(in lines: [String], before index: Int) -> String? {
        var i = index - 1
        while i >= 0 {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
            i -= 1
        }
        return nil
    }

    private static func nextNonBlank(in lines: [String], after index: Int) -> String? {
        var i = index + 1
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
            i += 1
        }
        return nil
    }
}
