//
//  EditorLogic.swift
//  Penova
//
//  Pure logic extracted from SceneDetailScreen so it can be unit tested
//  without a SwiftUI view hierarchy. SceneDetailScreen delegates its
//  Return/Tab/commit/autocomplete/ordering decisions to this type.
//

import Foundation

enum EditorLogic {

    // MARK: - Return key advancement

    /// Returns the element kind a new row should take when the user presses
    /// Return from a row of the given kind.
    static func nextKind(after kind: SceneElementKind) -> SceneElementKind {
        switch kind {
        case .heading:       return .action
        case .action:        return .action
        case .character:     return .dialogue
        case .dialogue:      return .action
        case .parenthetical: return .dialogue
        case .transition:    return .heading
        }
    }

    // MARK: - Tab cycle

    /// Returns the next kind when the user cycles the current row's kind
    /// (Tab on a hardware keyboard, or the accessory chip tap).
    /// Cycle order is the declared `allCases` order.
    static func tabCycle(from kind: SceneElementKind) -> SceneElementKind {
        let all = SceneElementKind.allCases
        guard let i = all.firstIndex(of: kind) else { return .action }
        return all[(i + 1) % all.count]
    }

    // MARK: - Commit normalisation

    /// Commit-time normalisation applied when a row loses focus or Return
    /// advances past it. Mirrors `SceneDetailScreen.commitNormalisation`
    /// plus the parenthetical wrapping used by the FDX writer.
    static func normalise(text: String, kind: SceneElementKind) -> String {
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
        }
    }

    // MARK: - Character autocomplete

    /// Case-insensitive substring match over the supplied character names.
    /// An empty or whitespace-only query returns every name in the original
    /// order. Results preserve the input order.
    static func suggestions(query: String, in names: [String]) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        if q.isEmpty { return names }
        return names.filter { $0.uppercased().contains(q) }
    }

    // MARK: - Order math

    /// Next order value when appending after `anchor`. If `anchor` is nil
    /// the caller is appending to an empty list → 0.
    static func nextOrder(after anchor: Int?) -> Int {
        guard let anchor else { return 0 }
        return anchor + 1
    }

    /// Midpoint order value when inserting between two adjacent rows. If
    /// there is no room (gap < 2) the caller must compact — we return nil
    /// to signal that.
    static func insertOrder(between a: Int, and b: Int) -> Int? {
        let lo = min(a, b)
        let hi = max(a, b)
        guard hi - lo >= 2 else { return nil }
        return (lo + hi) / 2
    }

    /// Compacts a list of orders to 0,1,2… preserving input order.
    static func compact(_ orders: [Int]) -> [Int] {
        (0..<orders.count).map { $0 }
    }
}
