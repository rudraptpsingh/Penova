//
//  SceneReorder.swift
//  PenovaKit
//
//  Pure-Swift helpers for reordering scenes (and any other ordered
//  collection of @Model rows). Used by the Mac Index Cards drag-drop
//  and any future iOS reorder UI. Operates on simple [(id, order)]
//  lists so the math is tested without SwiftData.
//
//  After mutation the caller writes the new order: Int back onto each
//  @Model and saves the context.
//

import Foundation

public enum SceneReorder {

    /// Reorders an array of (id, order) entries, moving the item with
    /// the given id from its current position to a new index. Returns
    /// the new compact ordering (0..n-1) preserving the move.
    ///
    /// - Parameters:
    ///   - items: Existing [(id, order)] sorted by order ascending.
    ///   - movingID: The id to relocate.
    ///   - destinationIndex: 0..<count target index in the *output*
    ///     array. Pass `count` to move to end.
    /// - Returns: The new array of (id, order) with order = 0..n-1.
    public static func move(
        _ items: [(id: String, order: Int)],
        movingID: String,
        to destinationIndex: Int
    ) -> [(id: String, order: Int)] {
        guard let sourceIndex = items.firstIndex(where: { $0.id == movingID })
        else { return items }
        guard sourceIndex != destinationIndex else { return items }

        var working = items.sorted { $0.order < $1.order }
        let moved = working.remove(at: sourceIndex)

        // If we removed an earlier element, the destinationIndex shifts down by 1
        let adjusted = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        let clamped = max(0, min(working.count, adjusted))
        working.insert(moved, at: clamped)

        return working.enumerated().map { ($0.element.id, $0.offset) }
    }

    /// Inserts a new item between two existing orders. Returns the
    /// midpoint if there's room (gap >= 2), otherwise nil — caller
    /// should compact the list.
    public static func insertOrder(between a: Int, and b: Int) -> Int? {
        let lo = min(a, b)
        let hi = max(a, b)
        guard hi - lo >= 2 else { return nil }
        return (lo + hi) / 2
    }
}
