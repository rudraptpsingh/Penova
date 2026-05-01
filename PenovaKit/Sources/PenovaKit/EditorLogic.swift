//
//  EditorLogic.swift
//  Penova
//
//  Pure logic extracted from SceneDetailScreen so it can be unit tested
//  without a SwiftUI view hierarchy. SceneDetailScreen delegates its
//  Return/Tab/commit/autocomplete/ordering decisions to this type.
//

import Foundation
public enum EditorLogic {

    // MARK: - Return key advancement

    /// Returns the element kind a new row should take when the user presses
    /// Return from a row of the given kind.
    public static func nextKind(after kind: SceneElementKind) -> SceneElementKind {
        switch kind {
        case .heading:       return .action
        case .action:        return .action
        case .character:     return .dialogue
        case .dialogue:      return .action
        case .parenthetical: return .dialogue
        case .transition:    return .heading
        case .actBreak:      return .heading
        }
    }

    // MARK: - Tab cycle

    /// Returns the next kind when the user cycles the current row's kind
    /// (Tab on a hardware keyboard, or the accessory chip tap).
    /// Cycle order is the declared `allCases` order.
    public static func tabCycle(from kind: SceneElementKind) -> SceneElementKind {
        let all = SceneElementKind.allCases
        guard let i = all.firstIndex(of: kind) else { return .action }
        return all[(i + 1) % all.count]
    }

    // MARK: - Commit normalisation

    /// Commit-time normalisation applied when a row loses focus or Return
    /// advances past it. Mirrors `SceneDetailScreen.commitNormalisation`
    /// plus the parenthetical wrapping used by the FDX writer.
    public static func normalise(text: String, kind: SceneElementKind) -> String {
        switch kind {
        case .heading:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        case .character:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        case .transition:
            return text.uppercased()
        case .parenthetical:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return "" }
            if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") { return trimmed }
            return "(\(trimmed))"
        case .action, .dialogue:
            return text
        case .actBreak:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
    }

    // MARK: - Continued-dialogue marker

    /// Standard suffix used when the same character speaks again after
    /// an interruption (action line, transition) or across a page break.
    /// All-caps; trailing apostrophe-d is the WGA-conventional form.
    public static let contdSuffix = "(CONT'D)"

    /// Returns the bare character name, stripped of any standard suffix
    /// like `(CONT'D)`, `(V.O.)`, `(O.S.)`, `(O.C.)`. Used for matching
    /// "is this the same speaker as the previous cue?" — `JANE` should
    /// match `JANE (CONT'D)` and `JANE (V.O.)` so the marker logic
    /// recognises a continued speaker.
    public static func bareCharacterName(_ cue: String) -> String {
        var name = cue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip every trailing "(...)" group (handles "JANE (V.O.) (CONT'D)").
        while let openIdx = name.lastIndex(of: "("), name.hasSuffix(")") {
            name = String(name[..<openIdx]).trimmingCharacters(in: .whitespaces)
        }
        return name.uppercased()
    }

    /// Decides whether a character cue should carry the `(CONT'D)`
    /// suffix because the same character spoke earlier in the scene
    /// without an intervening character change. Skips any number of
    /// non-character elements between the two cues (Action, Transition,
    /// Parenthetical, etc.) — that's the convention every pro tool
    /// implements.
    ///
    /// Returns the cue text with the suffix appended (or unchanged if
    /// no continuation is detected, or if the suffix is already there).
    /// `previousCharacterCues` is the *ordered* list of every character
    /// cue earlier in the scene that wasn't followed by another
    /// character change before this one — typically just the most-recent
    /// preceding cue. Order doesn't matter for correctness; we only
    /// look at the last entry.
    public static func appendContdIfNeeded(
        cue: String,
        previousCharacterCue: String?
    ) -> String {
        let normalised = cue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalised.isEmpty else { return cue }
        // Already has the marker — leave alone (writer-typed override).
        if normalised.uppercased().contains(contdSuffix) { return normalised }
        guard let prev = previousCharacterCue,
              !prev.trimmingCharacters(in: .whitespaces).isEmpty
        else { return normalised }
        let bareCurrent = bareCharacterName(normalised)
        let barePrevious = bareCharacterName(prev)
        guard bareCurrent == barePrevious, !bareCurrent.isEmpty else {
            return normalised
        }
        // Preserve any non-CONT'D suffixes the writer typed
        // (e.g. "JANE (V.O.)" → "JANE (V.O.) (CONT'D)").
        return "\(normalised) \(contdSuffix)"
    }

    // MARK: - Character autocomplete

    /// Case-insensitive substring match over the supplied character names.
    /// An empty or whitespace-only query returns every name in the original
    /// order. Results preserve the input order.
    public static func suggestions(query: String, in names: [String]) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        if q.isEmpty { return names }
        return names.filter { $0.uppercased().contains(q) }
    }

    // MARK: - Order math

    /// Next order value when appending after `anchor`. If `anchor` is nil
    /// the caller is appending to an empty list → 0.
    public static func nextOrder(after anchor: Int?) -> Int {
        guard let anchor else { return 0 }
        return anchor + 1
    }

    /// Midpoint order value when inserting between two adjacent rows. If
    /// there is no room (gap < 2) the caller must compact — we return nil
    /// to signal that.
    public static func insertOrder(between a: Int, and b: Int) -> Int? {
        let lo = min(a, b)
        let hi = max(a, b)
        guard hi - lo >= 2 else { return nil }
        return (lo + hi) / 2
    }

    /// Compacts a list of orders to 0,1,2… preserving input order.
    public static func compact(_ orders: [Int]) -> [Int] {
        (0..<orders.count).map { $0 }
    }
}
