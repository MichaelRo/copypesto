// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("ChipHoverIntent")
struct ChipHoverIntentTests {
    private func settled(_ intent: inout ChipHoverIntent, at time: Double) {
        intent.tick(at: time)
    }

    @Test("resting on a chip opens its name only after the dwell")
    func whenPointerRests_thenNameOpensAfterTheDwell() {
        var intent = ChipHoverIntent()

        intent.pointerMoved(over: 0, at: 0)
        intent.tick(at: ChipHoverIntent.dwell - 0.01)
        #expect(intent.expanded == nil)

        intent.tick(at: ChipHoverIntent.dwell + 0.01)
        #expect(intent.expanded == 0)
    }

    @Test("passing quickly over chips opens nothing")
    func whenPointerCrossesQuickly_thenNothingOpens() {
        var intent = ChipHoverIntent()

        intent.pointerMoved(over: 0, at: 0)
        intent.pointerMoved(over: 1, at: 0.05)
        intent.pointerMoved(over: 2, at: 0.10)
        intent.tick(at: 0.10 + ChipHoverIntent.dwell - 0.01)

        #expect(intent.expanded == nil)
    }

    @Test("with a name open, moving to the next chip switches at once")
    func whenANameIsOpen_thenTheNextChipOpensImmediately() {
        var intent = ChipHoverIntent()
        intent.pointerMoved(over: 0, at: 0)
        intent.tick(at: 1)

        intent.pointerMoved(over: 1, at: 1.02)

        #expect(intent.expanded == 1)
    }

    @Test("leaving the row closes the name only after a short grace")
    func whenPointerLeaves_thenNameClosesAfterGrace() {
        var intent = ChipHoverIntent()
        intent.pointerMoved(over: 0, at: 0)
        intent.tick(at: 1)

        intent.pointerMoved(over: nil, at: 1.0)
        intent.tick(at: 1.0 + ChipHoverIntent.grace - 0.01)
        #expect(intent.expanded == 0)

        intent.tick(at: 1.0 + ChipHoverIntent.grace + 0.01)
        #expect(intent.expanded == nil)
    }

    @Test("coming back within the grace keeps the name open")
    func whenPointerReturnsInGrace_thenStaysOpen() {
        var intent = ChipHoverIntent()
        intent.pointerMoved(over: 0, at: 0)
        intent.tick(at: 1)
        intent.pointerMoved(over: nil, at: 1.0)

        intent.pointerMoved(over: 0, at: 1.05)
        intent.tick(at: 2)

        #expect(intent.expanded == 0)
    }

    @Test("just after a name closes, the next chip opens without waiting again")
    func whenRecentlyClosed_thenNextChipOpensAtOnce() {
        var intent = ChipHoverIntent()
        intent.pointerMoved(over: 0, at: 0)
        intent.tick(at: 1)
        intent.pointerMoved(over: nil, at: 1.0)
        intent.tick(at: 1.2)
        #expect(intent.expanded == nil)

        intent.pointerMoved(over: 2, at: 1.3)

        #expect(intent.expanded == 2)
    }

    @Test("after the warm window, the dwell applies again")
    func whenLongSinceClosed_thenDwellAppliesAgain() {
        var intent = ChipHoverIntent()
        intent.pointerMoved(over: 0, at: 0)
        intent.tick(at: 1)
        intent.pointerMoved(over: nil, at: 1.0)
        intent.tick(at: 1.2)

        intent.pointerMoved(over: 2, at: 1.2 + ChipHoverIntent.warmWindow + 0.5)

        #expect(intent.expanded == nil)
    }

    @Test("nothing is pending when idle, so no timer needs to run")
    func whenIdle_thenNotPending() {
        var intent = ChipHoverIntent()
        #expect(!intent.isPending)

        intent.pointerMoved(over: 0, at: 0)
        #expect(intent.isPending)

        intent.tick(at: 1)
        #expect(!intent.isPending)
    }
}

@Suite("ChipSlots")
struct ChipSlotsTests {
    private let rest: [CGFloat] = [24, 24, 24, 24]

    @Test("a point maps to the chip whose resting slot holds it, gaps included")
    func whenPointInRestSlot_thenThatChip() {
        #expect(ChipSlots.target(x: 10, restWidths: rest, spacing: 8, expanded: nil) == 0)
        #expect(ChipSlots.target(x: 27, restWidths: rest, spacing: 8, expanded: nil) == 0)
        #expect(ChipSlots.target(x: 29, restWidths: rest, spacing: 8, expanded: nil) == 1)
        #expect(ChipSlots.target(x: 100, restWidths: rest, spacing: 8, expanded: nil) == 3)
    }

    @Test("beyond the last slot there is no chip unless the last one is open and the point is inside its name")
    func whenPastTheEnd_thenNilUnlessInsideTheOpenLastChip() {
        #expect(ChipSlots.target(x: 140, restWidths: rest, spacing: 8, expanded: nil) == nil)
        let open = ChipSlots.Expanded(index: 3, width: 90)
        #expect(ChipSlots.target(x: 140, restWidths: rest, spacing: 8, expanded: open) == 3)
        #expect(ChipSlots.target(x: 200, restWidths: rest, spacing: 8, expanded: open) == nil)
    }

    @Test("a chip that is wider at rest, such as an active one, keeps its own wider slot")
    func whenAChipIsWiderAtRest_thenItsSlotIsWider() {
        let widths: [CGFloat] = [24, 90, 24]

        #expect(ChipSlots.target(x: 100, restWidths: widths, spacing: 8, expanded: nil) == 1)
        #expect(ChipSlots.target(x: 134, restWidths: widths, spacing: 8, expanded: nil) == 2)
    }

    @Test("the pointer may go well into an open name before the next chip takes over")
    func whenANameIsOpen_thenThePointerKeepsItFarIntoTheName() {
        let open = ChipSlots.Expanded(index: 0, width: 100)
        let reach = 24 + 4 + ChipSlots.reachShare * 76

        #expect(ChipSlots.target(x: 28, restWidths: rest, spacing: 8, expanded: nil) == 1)
        #expect(ChipSlots.target(x: 28, restWidths: rest, spacing: 8, expanded: open) == 0)
        #expect(ChipSlots.target(x: reach - 1, restWidths: rest, spacing: 8, expanded: open) == 0)
        #expect(ChipSlots.target(x: reach + 1, restWidths: rest, spacing: 8, expanded: open) == 1)
    }

    @Test("every chip after the open one is matched the same distance farther, so none is skipped")
    func whenANameIsOpen_thenLaterChipsKeepTheirOrderAndSize() {
        let open = ChipSlots.Expanded(index: 0, width: 100)
        let reach = ChipSlots.reachShare * 76
        var seen: [Int] = []
        var x: CGFloat = 0
        while x < 24 + 3 * 32 + reach {
            if let index = ChipSlots.target(x: x, restWidths: rest, spacing: 8, expanded: open), seen.last != index {
                seen.append(index)
            }
            x += 1
        }

        #expect(seen == [0, 1, 2, 3])
    }

    @Test("no chips, no target")
    func whenEmpty_thenNil() {
        #expect(ChipSlots.target(x: 5, restWidths: [], spacing: 8, expanded: nil) == nil)
    }
}
