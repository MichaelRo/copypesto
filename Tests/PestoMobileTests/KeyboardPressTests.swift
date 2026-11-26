// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing

@Suite("A touch on a keyboard card is a tap, a hold, or a scroll")
struct KeyboardPressTests {
    private let start = CGPoint(x: 100, y: 40)

    @Test("a touch lifted before the hold delay is a tap")
    func whenLiftedEarly_thenTap() {
        var press = KeyboardPress(start: start, allowsHold: true)
        press.moved(to: CGPoint(x: 103, y: 42))
        press.ended()
        #expect(press.outcome == .tap)
        #expect(!press.isFailed)
    }

    @Test("a touch that moves past the slop fails, so the row scrolls and nothing is inserted")
    func whenMovedPastSlop_thenFails() {
        var press = KeyboardPress(start: start, allowsHold: true)
        press.moved(to: CGPoint(x: 100 - KeyboardPress.slop - 1, y: 40))
        press.holdElapsed()
        press.ended()
        #expect(press.isFailed)
        #expect(press.outcome == nil)
    }

    @Test("a touch held still past the delay is a hold, and lifting it adds no tap")
    func whenHeld_thenHoldOnly() {
        var press = KeyboardPress(start: start, allowsHold: true)
        press.holdElapsed()
        #expect(press.outcome == .hold)
        press.ended()
        #expect(press.outcome == .hold)
    }

    @Test("on a card without a hold action, a long touch is neither, so the context menu can take it")
    func whenHoldNotAllowed_thenLongTouchFails() {
        var press = KeyboardPress(start: start, allowsHold: false)
        press.holdElapsed()
        press.ended()
        #expect(press.isFailed)
        #expect(press.outcome == nil)
    }

    @Test("a hold that has fired is not undone by moving afterwards")
    func whenMovedAfterHold_thenStillHold() {
        var press = KeyboardPress(start: start, allowsHold: true)
        press.holdElapsed()
        press.moved(to: CGPoint(x: 160, y: 40))
        #expect(press.outcome == .hold)
        #expect(!press.isFailed)
    }
}
