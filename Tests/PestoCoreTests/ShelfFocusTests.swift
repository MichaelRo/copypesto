// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("ShelfFocus")
struct ShelfFocusTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), fresh = UUID()

    @Test("a clip copied while the shelf is open does not move the focus ring to another clip")
    func whenANewClipArrivesAtTheFront_thenFocusStaysOnItsClip() {
        let index = ShelfFocus.resolvedIndex(focusedID: c, previousIndex: 2, in: [fresh, a, b, c, d])

        #expect(index == 3)
    }

    @Test("focus on the newest clip stays on the newest when another arrives")
    func whenFocusIsOnTheNewest_thenItStaysAtTheFront() {
        let index = ShelfFocus.resolvedIndex(focusedID: a, previousIndex: 0, in: [fresh, a, b, c])

        #expect(index == 0)
    }

    @Test("deleting a clip above the focus keeps the focus on its clip")
    func whenAClipAboveIsDeleted_thenFocusFollowsItsClip() {
        let index = ShelfFocus.resolvedIndex(focusedID: c, previousIndex: 3, in: [a, c, d])

        #expect(index == 1)
    }

    @Test("when the focused clip is gone, focus stays on its slot, which the next clip now fills")
    func whenTheFocusedClipIsDeleted_thenTheNextClipIsFocused() {
        let index = ShelfFocus.resolvedIndex(focusedID: b, previousIndex: 1, in: [a, c, d])

        #expect(index == 1)
    }

    @Test("when the focused clip was the last, focus lands on the new last clip")
    func whenTheLastClipIsDeleted_thenFocusClamps() {
        let index = ShelfFocus.resolvedIndex(focusedID: d, previousIndex: 3, in: [a, b, c])

        #expect(index == 2)
    }

    @Test("no clips means focus at zero")
    func whenEmpty_thenZero() {
        #expect(ShelfFocus.resolvedIndex(focusedID: a, previousIndex: 4, in: []) == 0)
    }

    @Test("without a remembered clip, the index is only clamped")
    func whenNothingIsRemembered_thenTheIndexIsKept() {
        #expect(ShelfFocus.resolvedIndex(focusedID: nil, previousIndex: 2, in: [a, b, c, d]) == 2)
        #expect(ShelfFocus.resolvedIndex(focusedID: nil, previousIndex: 9, in: [a, b]) == 1)
    }
}
