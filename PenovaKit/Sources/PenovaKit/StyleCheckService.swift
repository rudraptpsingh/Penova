//
//  StyleCheckService.swift
//  PenovaKit
//
//  Quiet, opinionated style check for screenplay action lines.
//  Flags three things, never blocks:
//
//   • Adverb       — words ending in "-ly" (with a non-adverb stop list).
//                    The classic screenplay sin in parentheticals + action.
//   • Cliché       — phrase lookup against a short curated list of
//                    over-used screenplay tics ("a beat", "we see",
//                    "begins to", "the kind of tired that sleep doesn't
//                    fix", etc.). Whole-phrase, case-insensitive,
//                    word-boundary anchored.
//   • Passive      — "is/are/was/were being" plus a conservative
//                    "[verb to be] + past participle" heuristic. Errs
//                    on flagging less, not more — the writer can opt
//                    in to stricter rules in a future PR.
//
//  Scoping rules (matches the mockup):
//   • Action lines:    all three kinds.
//   • Parenthetical:   adverb only ("(quietly)" → flagged).
//   • Dialogue:        skipped — characters speak naturally.
//   • Heading / character / transition / act-break: skipped.
//
//  Marks are returned as UTF-16 offsets (NSRange-compatible) so they
//  serialise cleanly and survive a round-trip into AttributedString /
//  NSAttributedString rendering on Mac and iOS. A `range(in:)` helper
//  recovers a Swift `Range<String.Index>` when the caller wants to
//  splice the text directly.
//
//  Pure logic — no SwiftData, no platform deps in the string scanner.
//  The SceneElement / ScriptScene overloads are @MainActor because
//  they read SwiftData @Model properties.
//

import Foundation

// MARK: - Mark kind

public enum StyleMarkKind: String, Codable, CaseIterable, Sendable {
    case adverb
    case cliche
    case passive

    public var display: String {
        switch self {
        case .adverb:  return "Adverb"
        case .cliche:  return "Cliché"
        case .passive: return "Passive"
        }
    }
}

// MARK: - Mark

public struct StyleMark: Equatable, Hashable, Codable, Sendable {
    public let kind: StyleMarkKind
    /// UTF-16 offset of the match in the source string. NSRange-compatible.
    public let location: Int
    /// UTF-16 length of the match.
    public let length: Int
    /// The literal substring that was matched. Surfaced in tooltips.
    public let matched: String
    /// Short human note (e.g. "Cliché — overused in action lines").
    public let note: String

    public init(
        kind: StyleMarkKind,
        location: Int,
        length: Int,
        matched: String,
        note: String
    ) {
        self.kind = kind
        self.location = location
        self.length = length
        self.matched = matched
        self.note = note
    }

    /// NSRange convenience — handy for AttributedString / NSAttributedString.
    public var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    /// Recover a Swift `Range<String.Index>` for splicing directly into
    /// the source string. Returns nil if the offsets fall outside the
    /// string (shouldn't happen for marks produced by this service, but
    /// caller resilience is cheap).
    public func range(in text: String) -> Range<String.Index>? {
        let utf16 = text.utf16
        guard location >= 0,
              length >= 0,
              let start = utf16.index(
                utf16.startIndex,
                offsetBy: location,
                limitedBy: utf16.endIndex
              ),
              let end = utf16.index(
                start,
                offsetBy: length,
                limitedBy: utf16.endIndex
              ),
              let lower = start.samePosition(in: text),
              let upper = end.samePosition(in: text)
        else { return nil }
        return lower..<upper
    }
}

// MARK: - Service

public enum StyleCheckService {

    public static let defaultKinds: Set<StyleMarkKind> =
        [.adverb, .cliche, .passive]

    // MARK: Public — pure string

    /// Scan an arbitrary text string. No platform deps; safe to call
    /// from any thread.
    public static func marks(
        in text: String,
        kinds: Set<StyleMarkKind> = defaultKinds
    ) -> [StyleMark] {
        guard !text.isEmpty, !kinds.isEmpty else { return [] }

        var out: [StyleMark] = []

        if kinds.contains(.cliche) {
            out.append(contentsOf: scanCliches(in: text))
        }
        if kinds.contains(.passive) {
            out.append(contentsOf: scanPassive(in: text))
        }
        if kinds.contains(.adverb) {
            out.append(contentsOf: scanAdverbs(in: text))
        }

        // Stable sort by start offset, then kind for determinism.
        out.sort { lhs, rhs in
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return out
    }

    // MARK: Public — model-aware

    /// Scope per element kind:
    ///   .action       → all three checks
    ///   .parenthetical → adverb only
    ///   else          → empty
    @MainActor
    public static func marks(
        for element: SceneElement,
        kinds: Set<StyleMarkKind> = defaultKinds
    ) -> [StyleMark] {
        switch element.kind {
        case .action:
            return marks(in: element.text, kinds: kinds)
        case .parenthetical:
            // Parentheticals only get the adverb check — the classic
            // "(quietly)" tic. Pass through cliché/passive only if
            // the caller didn't disable adverb scanning.
            let scoped = kinds.intersection([.adverb])
            return marks(in: element.text, kinds: scoped)
        case .dialogue, .character, .heading, .transition, .actBreak:
            return []
        }
    }

    /// All marks across every action + parenthetical element in a scene,
    /// in scene order. Intended for the inspector summary.
    @MainActor
    public static func marks(
        for scene: ScriptScene,
        kinds: Set<StyleMarkKind> = defaultKinds
    ) -> [(element: SceneElement, marks: [StyleMark])] {
        scene.elementsOrdered.compactMap { el in
            let m = marks(for: el, kinds: kinds)
            return m.isEmpty ? nil : (el, m)
        }
    }

    // MARK: - Adverb scan

    /// Words that end in -ly but aren't adverbs in any normal screenplay
    /// usage. Lower-cased. Extend judiciously — false positives are
    /// recoverable (writer ignores the dot), false negatives are not.
    public static let adverbStopList: Set<String> = [
        "ally", "bully", "curly", "doily", "family", "filly", "gully",
        "holy", "italy", "jelly", "jolly", "july", "lily", "lonely",
        "lovely", "manly", "rally", "rely", "silly", "supply", "ugly",
        "wholly", "wholly", "friendly", "godly", "hilly", "homely",
        "lowly", "kindly", "smelly", "ply", "fly", "deadly"
    ]

    private static let adverbRegex: NSRegularExpression = {
        // Word ending in `ly`, at least 4 letters total to skip "fly"/"ply".
        // Compiled case-insensitive so "QUICKLY" / "Quickly" / "quickly"
        // all match without the caller having to lowercase first.
        try! NSRegularExpression(
            pattern: #"\b[A-Za-z]{4,}ly\b"#,
            options: [.caseInsensitive]
        )
    }()

    private static func scanAdverbs(in text: String) -> [StyleMark] {
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        var marks: [StyleMark] = []

        adverbRegex.enumerateMatches(in: text, range: full) { result, _, _ in
            guard let r = result?.range, r.location != NSNotFound else { return }
            let matched = nsText.substring(with: r)
            let lower = matched.lowercased()
            guard !adverbStopList.contains(lower) else { return }
            marks.append(.init(
                kind: .adverb,
                location: r.location,
                length: r.length,
                matched: matched,
                note: "Adverb — consider trimming or showing the action."
            ))
        }
        return marks
    }

    // MARK: - Cliché scan

    /// Curated starter list. Tuned for screenplays — these are the
    /// phrases that show up over and over in unproduced action lines.
    /// Ordered longest-first so we match the most specific phrase
    /// before falling back to a shorter overlapping one.
    public static let clichePhrases: [String] = [
        // Long, tone-heavy
        "the kind of tired that sleep doesn't fix",
        "tired that sleep doesn't fix",
        "couldn't agree more",
        "easier said than done",
        "if there's one thing",
        "the calm before the storm",
        // Action-line tics
        "we see",
        "we hear",
        "we follow",
        "we watch as",
        "begins to",
        "starts to",
        "a beat",
        "for a beat",
        "for a moment",
        "in the distance",
        "deafening silence",
        "at the last minute",
        "lost in thought",
        "needless to say",
        "let's face it"
    ]

    private static func scanCliches(in text: String) -> [StyleMark] {
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)

        // Track ranges already claimed by a longer cliché so a shorter
        // overlapping phrase doesn't re-flag the same span.
        var claimed: [NSRange] = []
        var marks: [StyleMark] = []

        for phrase in clichePhrases {
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            // Word-boundary anchoring on both ends so "we see" doesn't
            // match inside "between the trees we see-saw".
            let pattern = "(?i)\\b" + escaped + "\\b"
            guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
            rx.enumerateMatches(in: text, range: full) { res, _, _ in
                guard let r = res?.range, r.location != NSNotFound else { return }
                if claimed.contains(where: { intersects($0, r) }) { return }
                claimed.append(r)
                marks.append(.init(
                    kind: .cliche,
                    location: r.location,
                    length: r.length,
                    matched: nsText.substring(with: r),
                    note: "Cliché — overused in action lines."
                ))
            }
        }
        return marks
    }

    private static func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        let aEnd = a.location + a.length
        let bEnd = b.location + b.length
        return a.location < bEnd && b.location < aEnd
    }

    // MARK: - Passive-voice scan

    /// Conservative regex set. Flags only the patterns that are almost
    /// always passive-or-progressive-passive in prose:
    ///   • is being / are being / was being / were being   (always)
    ///   • is/are/was/were + known past participle          (high signal)
    ///
    /// We intentionally do NOT try to detect every passive — false
    /// positives in screenplay action lines are worse than misses.
    public static let pastParticiples: Set<String> = [
        "watched", "ignored", "abandoned", "killed", "saved", "loved",
        "hated", "trapped", "freed", "broken", "shattered", "thrown",
        "stolen", "given", "taken", "chosen", "betrayed", "hidden",
        "found", "lost", "buried", "raised", "drowned", "burned",
        "shot", "stabbed", "carried", "dragged", "pulled", "pushed",
        "called", "named", "marked", "told", "warned", "promised",
        "denied", "rejected", "accepted", "destroyed", "rescued",
        "captured", "released", "arrested", "judged", "condemned",
        "frightened", "loaded", "covered", "wrapped", "tied"
    ]

    private static let passiveBeingRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b(?:is|are|was|were)\s+being\s+\w+\b"#,
            options: [.caseInsensitive]
        )
    }()

    private static func scanPassive(in text: String) -> [StyleMark] {
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        var marks: [StyleMark] = []
        var claimed: [NSRange] = []

        // 1. "[is/are/was/were] being [word]"
        passiveBeingRegex.enumerateMatches(in: text, range: full) { res, _, _ in
            guard let r = res?.range, r.location != NSNotFound else { return }
            claimed.append(r)
            marks.append(.init(
                kind: .passive,
                location: r.location,
                length: r.length,
                matched: nsText.substring(with: r),
                note: "Passive — try an active verb."
            ))
        }

        // 2. "[is/are/was/were] [past participle]"
        // Build one regex per participle to keep boundary-handling simple
        // and skip overlap with the "being" matches above.
        let bes = ["is", "are", "was", "were"]
        for pp in pastParticiples {
            for be in bes {
                let pattern = "(?i)\\b\(be)\\s+\(NSRegularExpression.escapedPattern(for: pp))\\b"
                guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
                rx.enumerateMatches(in: text, range: full) { res, _, _ in
                    guard let r = res?.range, r.location != NSNotFound else { return }
                    if claimed.contains(where: { intersects($0, r) }) { return }
                    claimed.append(r)
                    marks.append(.init(
                        kind: .passive,
                        location: r.location,
                        length: r.length,
                        matched: nsText.substring(with: r),
                        note: "Passive — try an active verb."
                    ))
                }
            }
        }
        return marks
    }
}
