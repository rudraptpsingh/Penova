//
//  SceneReorderTests.swift
//  PenovaTests
//
//  Drag-to-reorder math used by the Mac Index Cards drop handler.
//

import Testing
@testable import PenovaKit

@Suite("SceneReorder")
struct SceneReorderTests {
    private let scenes: [(id: String, order: Int)] = [
        ("a", 0), ("b", 1), ("c", 2), ("d", 3), ("e", 4),
    ]

    private func ids(_ result: [(id: String, order: Int)]) -> [String] {
        result.map(\.id)
    }

    @Test("identity move returns input unchanged")
    func identityMove() {
        let r = SceneReorder.move(scenes, movingID: "c", to: 2)
        #expect(ids(r) == ["a", "b", "c", "d", "e"])
    }

    @Test("move first to last")
    func firstToLast() {
        let r = SceneReorder.move(scenes, movingID: "a", to: 5)
        #expect(ids(r) == ["b", "c", "d", "e", "a"])
        #expect(r.map(\.order) == [0, 1, 2, 3, 4])
    }

    @Test("move last to first")
    func lastToFirst() {
        let r = SceneReorder.move(scenes, movingID: "e", to: 0)
        #expect(ids(r) == ["e", "a", "b", "c", "d"])
        #expect(r.map(\.order) == [0, 1, 2, 3, 4])
    }

    @Test("move middle to before first")
    func middleToFront() {
        let r = SceneReorder.move(scenes, movingID: "c", to: 0)
        #expect(ids(r) == ["c", "a", "b", "d", "e"])
    }

    @Test("move middle to after last")
    func middleToBack() {
        let r = SceneReorder.move(scenes, movingID: "c", to: 5)
        #expect(ids(r) == ["a", "b", "d", "e", "c"])
    }

    @Test("move forward respects shift-down semantics")
    func moveForwardShift() {
        // Move "b" to index 3 — after we remove "b" the destination shifts
        // so the result should land "b" between "c"/"d" and "d"/"e".
        let r = SceneReorder.move(scenes, movingID: "b", to: 3)
        #expect(ids(r) == ["a", "c", "b", "d", "e"])
    }

    @Test("move backward keeps destination")
    func moveBackward() {
        let r = SceneReorder.move(scenes, movingID: "d", to: 1)
        #expect(ids(r) == ["a", "d", "b", "c", "e"])
    }

    @Test("unknown id returns input unchanged")
    func unknownID() {
        let r = SceneReorder.move(scenes, movingID: "zzz", to: 0)
        #expect(ids(r) == ["a", "b", "c", "d", "e"])
    }

    @Test("destination clamped to bounds")
    func clamped() {
        let r1 = SceneReorder.move(scenes, movingID: "c", to: 999)
        #expect(ids(r1) == ["a", "b", "d", "e", "c"])
        let r2 = SceneReorder.move(scenes, movingID: "c", to: -5)
        #expect(ids(r2) == ["c", "a", "b", "d", "e"])
    }

    @Test("compacted output: orders are 0..n-1")
    func compacted() {
        let r = SceneReorder.move(scenes, movingID: "c", to: 0)
        #expect(r.map(\.order) == [0, 1, 2, 3, 4])
    }

    @Test("insertOrder midpoint when gap >= 2")
    func insertOrderMidpoint() {
        #expect(SceneReorder.insertOrder(between: 0, and: 10) == 5)
        #expect(SceneReorder.insertOrder(between: 10, and: 0) == 5)
        #expect(SceneReorder.insertOrder(between: 0, and: 2) == 1)
    }

    @Test("insertOrder nil when no room")
    func insertOrderNoRoom() {
        #expect(SceneReorder.insertOrder(between: 0, and: 1) == nil)
        #expect(SceneReorder.insertOrder(between: 5, and: 5) == nil)
    }
}
