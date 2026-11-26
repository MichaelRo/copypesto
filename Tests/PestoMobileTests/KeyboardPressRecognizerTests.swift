// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
import UIKit

/// The card's recognizer as UIKit drives it: it reports a tap or a hold through its action (what the SwiftUI card acts
/// on), and reports nothing, never holding the touch, once the finger moves or the scroll view takes the touch.
@Suite("The keyboard card's recognizer")
@MainActor
struct KeyboardPressRecognizerTests {
    /// What the recognizer reported, in order, as the card's action sees it.
    private final class Recorder: NSObject {
        var outcomes: [KeyboardPress.Outcome] = []

        @objc
        func fired(_ recognizer: KeyboardPressRecognizer) {
            if recognizer.state == .ended, let outcome = recognizer.outcome { outcomes.append(outcome) }
        }
    }

    private let start = CGPoint(x: 80, y: 40)
    /// UIKit runs a recognizer only while it is attached to a view.
    private let card = UIView(frame: CGRect(x: 0, y: 0, width: 150, height: 88))
    private let recorder = Recorder()

    private func recognizer(allowsHold: Bool = true) -> KeyboardPressRecognizer {
        let recognizer = KeyboardPressRecognizer(target: recorder, action: #selector(Recorder.fired(_:)))
        card.addGestureRecognizer(recognizer)
        recognizer.allowsHold = allowsHold
        recognizer.holdDelay = .milliseconds(30)
        return recognizer
    }

    private func waitPastHold() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    @Test("a quick touch reports one tap when it lifts")
    func whenLifted_thenTap() async throws {
        let press = recognizer()
        press.began(at: start)
        press.ended()
        try await waitPastHold()
        #expect(recorder.outcomes == [.tap])
    }

    @Test("a still touch reports one hold while the finger is down, and lifting it adds no tap")
    func whenHeld_thenHoldOnly() async throws {
        let press = recognizer()
        press.began(at: start)
        try await waitPastHold()
        #expect(recorder.outcomes == [.hold])
        press.ended()
        try await waitPastHold()
        #expect(recorder.outcomes == [.hold])
    }

    @Test("a touch that moves past the slop reports nothing, then or when it lifts or stays")
    func whenMoved_thenNothing() async throws {
        let press = recognizer()
        press.began(at: start)
        press.moved(to: CGPoint(x: start.x - KeyboardPress.slop - 2, y: start.y))
        try await waitPastHold()
        press.ended()
        #expect(recorder.outcomes.isEmpty)
    }

    @Test("a touch the scroll view takes reports nothing, and no hold fires after")
    func whenCancelled_thenNothing() async throws {
        let press = recognizer()
        press.began(at: start)
        press.cancelled()
        try await waitPastHold()
        #expect(recorder.outcomes.isEmpty)
    }

    @Test("a second finger fails the press")
    func whenSecondFinger_thenNothing() async throws {
        let press = recognizer()
        press.began(at: start)
        press.began(at: CGPoint(x: 120, y: 40))
        press.ended()
        try await waitPastHold()
        #expect(recorder.outcomes.isEmpty)
    }

    @Test("on a picture, which has no hold, a long touch reports nothing so its menu can take it")
    func whenHoldNotAllowed_thenLongTouchReportsNothing() async throws {
        let press = recognizer(allowsHold: false)
        press.began(at: start)
        try await waitPastHold()
        press.ended()
        #expect(recorder.outcomes.isEmpty)
    }

    @Test("one press after another each report their own tap")
    func whenPressedTwice_thenTwoTaps() async throws {
        let press = recognizer()
        press.began(at: start)
        press.ended()
        try await waitPastHold()
        press.reset()
        press.began(at: start)
        press.ended()
        try await waitPastHold()
        #expect(recorder.outcomes == [.tap, .tap])
    }
}
