// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Testing
@testable import PestoCore

@Suite("Reordering collection chips by dragging")
struct CollectionReorderTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test("dropped on the leading half of a chip, the dragged chip lands before it")
    func whenBefore_thenInsertedBefore() {
        #expect(CollectionReorder.order([a, b, c, d], moving: d, relativeTo: b, side: .before) == [a, d, b, c])
    }

    @Test("dropped on the trailing half, it lands after it, also when it came from earlier in the row")
    func whenAfter_thenInsertedAfter() {
        #expect(CollectionReorder.order([a, b, c, d], moving: a, relativeTo: c, side: .after) == [b, c, a, d])
    }

    @Test("dropping a chip on itself, or on an unknown chip, changes nothing")
    func whenNoRealTarget_thenUnchanged() {
        #expect(CollectionReorder.order([a, b], moving: a, relativeTo: a, side: .after) == [a, b])
        #expect(CollectionReorder.order([a, b], moving: a, relativeTo: UUID(), side: .after) == [a, b])
    }

    @Test("the pointer's half picks the side")
    func whenPointerInHalf_thenSide() {
        #expect(CollectionReorder.Side.at(x: 10, width: 100) == .before)
        #expect(CollectionReorder.Side.at(x: 60, width: 100) == .after)
    }

    @Test("the insertion index counts the chips whose centre the pointer has passed")
    func whenPointerMoves_thenIndexFollows() {
        let mids: [CGFloat] = [50, 150, 250]
        #expect(CollectionReorder.insertionIndex(slotMidXs: mids, pointerX: 10, currentIndex: 0) == 0)
        #expect(CollectionReorder.insertionIndex(slotMidXs: mids, pointerX: 200, currentIndex: 0) == 2)
        #expect(CollectionReorder.insertionIndex(slotMidXs: mids, pointerX: 400, currentIndex: 0) == 3)
    }

    @Test("a pointer resting just past a centre does not flip the order back and forth")
    func whenOnABoundary_thenTheDeadbandHoldsTheCurrentSide() {
        let mids: [CGFloat] = [50, 150]
        // Currently after the first chip (index 1): 4 pt left of its centre is still within the band.
        #expect(CollectionReorder.insertionIndex(slotMidXs: mids, pointerX: 46, currentIndex: 1) == 1)
        // Currently before it (index 0): 4 pt right of its centre is still within the band.
        #expect(CollectionReorder.insertionIndex(slotMidXs: mids, pointerX: 54, currentIndex: 0) == 0)
        // Past the band, it changes sides.
        #expect(CollectionReorder.insertionIndex(slotMidXs: mids, pointerX: 60, currentIndex: 0) == 1)
        #expect(CollectionReorder.insertionIndex(slotMidXs: mids, pointerX: 40, currentIndex: 1) == 0)
    }

    @Test("a chip is put back at an index among the others")
    func whenMovedToIndex_thenOrdered() {
        #expect(CollectionReorder.order([a, b, c, d], moving: d, toIndex: 1) == [a, d, b, c])
        #expect(CollectionReorder.order([a, b, c, d], moving: a, toIndex: 9) == [b, c, d, a])
    }
}
