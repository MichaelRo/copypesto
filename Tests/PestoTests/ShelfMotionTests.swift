// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import Pesto

@Suite("Shelf motion")
struct ShelfMotionTests {
    private let ids = (0..<6).map { _ in UUID() }

    @Test("one clip added or removed is animated")
    func whenOneAddedOrRemoved_thenAnimated() {
        let list = Array(ids.prefix(4))

        #expect(ShelfMotion.shouldAnimateChange(from: list, to: [ids[4]] + list))
        #expect(ShelfMotion.shouldAnimateChange(from: list, to: Array(list.dropFirst())))
        #expect(ShelfMotion.shouldAnimateChange(from: list, to: list.filter { $0 != ids[2] }))
    }

    @Test("one clip swapped for another is animated")
    func whenOneSwappedForAnother_thenAnimated() {
        let list = Array(ids.prefix(4))

        #expect(ShelfMotion.shouldAnimateChange(from: list, to: [ids[5]] + Array(list.dropFirst())))
    }

    @Test("a clip brought to the front is animated, any other reordering is not")
    func whenReordered_thenOnlyMoveToFrontAnimates() {
        let list = Array(ids.prefix(4))

        #expect(ShelfMotion.shouldAnimateChange(from: list, to: [list[2], list[0], list[1], list[3]]))
        #expect(!ShelfMotion.shouldAnimateChange(from: list, to: Array(list.reversed())))
        #expect(!ShelfMotion.shouldAnimateChange(from: list, to: [list[1], list[0], list[3], list[2]]))
    }

    @Test("a search or filter that rewrites the list, and no change at all, are not animated")
    func whenListRewritten_thenNotAnimated() {
        let list = Array(ids.prefix(4))

        #expect(!ShelfMotion.shouldAnimateChange(from: list, to: Array(list.prefix(1))))
        #expect(!ShelfMotion.shouldAnimateChange(from: list, to: Array(ids.suffix(3))))
        #expect(!ShelfMotion.shouldAnimateChange(from: list, to: list))
        #expect(!ShelfMotion.shouldAnimateChange(from: [], to: []))
    }

    @Test("the shelf slides forward to a later collection and back to an earlier one")
    func whenSwitchingCollection_thenDirectionFollowsTheChips() {
        let a = UUID()
        let b = UUID()
        let order: [UUID?] = [nil, a, b]

        #expect(ShelfMotion.switchDirection(order: order, from: nil, to: a) == 1)
        #expect(ShelfMotion.switchDirection(order: order, from: a, to: b) == 1)
        #expect(ShelfMotion.switchDirection(order: order, from: b, to: nil) == -1)
        #expect(
            ShelfMotion.switchDirection(order: order, from: UUID(), to: a) == 1,
            "an unknown collection falls back to forward"
        )
    }
}
