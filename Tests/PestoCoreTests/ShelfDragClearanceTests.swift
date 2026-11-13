// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("The shelf gets out of the way of a dragged clip only once the pointer leaves it")
struct ShelfDragClearanceTests {
    private let panel = CGRect(x: 0, y: 100, width: 1500, height: 300)
    private let onCards = CGPoint(x: 400, y: 200)
    private let onChips = CGPoint(x: 400, y: 390)
    private let above = CGPoint(x: 400, y: 600)

    private func run(_ pointers: [CGPoint]) -> [ShelfDragClearance.Step] {
        var phase = ShelfDragClearance.Phase.insidePanel
        return pointers.map {
            let step = ShelfDragClearance.step(pointer: $0, panelFrame: panel, phase: phase)
            phase = step.phase
            return step
        }
    }

    @Test("at the start of a drag on a card the shelf stays visible and live")
    func whenDragStartsOnACard_thenLive() {
        let step = run([onCards])[0]
        #expect(step.isLive)
        #expect(step.phase == .insidePanel)
    }

    @Test("moving up first reaches the collection chips with the shelf live all the way")
    func whenPointerGoesUpFirst_thenChipsStayLive() {
        let steps = run([onCards, CGPoint(x: 400, y: 300), onChips])
        let live = steps.map(\.isLive)
        #expect(!live.contains(false))
        #expect(steps.allSatisfy { $0.phase == .insidePanel })
    }

    @Test("moving sideways first keeps the shelf live while inside the panel")
    func whenPointerGoesSidewaysFirst_thenLive() {
        let steps = run([onCards, CGPoint(x: 900, y: 200), CGPoint(x: 900, y: 390)])
        let live = steps.map(\.isLive)
        #expect(!live.contains(false))
    }

    @Test("leaving the panel clears the shelf so the app behind takes the drop")
    func whenPointerLeavesThePanel_thenCleared() {
        let step = run([onCards, above])[1]
        #expect(!step.isLive)
        #expect(step.phase == .cleared)
    }

    @Test("after clearing, coming back over the chip strip makes the shelf live again")
    func whenLeftAndReturnedToChips_thenLive() {
        let steps = run([onCards, above, onChips])
        #expect(steps[2].isLive)
        #expect(steps[2].phase == .cleared)
    }

    @Test("after clearing, coming back over the cards stays click-through")
    func whenLeftAndReturnedToCards_thenStaysCleared() {
        let steps = run([onCards, above, onCards])
        #expect(!steps[2].isLive)
        #expect(steps[2].phase == .cleared)
    }

    @Test("a drag that starts outside the panel clears at once")
    func whenPointerStartsOutside_thenCleared() {
        let step = run([above])[0]
        #expect(!step.isLive)
        #expect(step.phase == .cleared)
    }
}

@Suite("The drag flag outlives the 3 second fallback while the button is down")
struct DragStateFallbackTests {
    @Test("a drag still held is checked again, not cleared")
    func whenButtonStillDown_thenCheckAgain() {
        #expect(DragStateFallback.decide(stillThisDrag: true, buttonDown: true) == .checkAgain)
    }

    @Test("a drag whose button is up is cleared")
    func whenButtonUp_thenClear() {
        #expect(DragStateFallback.decide(stillThisDrag: true, buttonDown: false) == .clear)
    }

    @Test("a newer drag or an already cleared one is left alone")
    func whenNotThisDrag_thenStop() {
        #expect(DragStateFallback.decide(stillThisDrag: false, buttonDown: true) == .stop)
        #expect(DragStateFallback.decide(stillThisDrag: false, buttonDown: false) == .stop)
    }
}
