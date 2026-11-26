// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// A card's tap and hold as one UIKit recognizer. SwiftUI's `onTapGesture` and `onLongPressGesture` on every card held
/// a touch that started on a card until it had moved far enough, so reversing the row mid-glide felt stuck; this one
/// fails at the first movement past `KeyboardPress.slop` and when the scroll view cancels its touches.
final class KeyboardPressRecognizer: UIGestureRecognizer {
    var allowsHold = true
    /// Shorter in a test, which waits for it.
    var holdDelay = KeyboardPress.holdDelay
    private(set) var outcome: KeyboardPress.Outcome?
    private var press: KeyboardPress?
    private var holdTask: Task<Void, Never>?
    private var isOver = false

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent) {
        guard touches.count == 1, let touch = touches.first else { return fail() }
        began(at: touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent) {
        guard let touch = touches.first else { return }
        moved(to: touch.location(in: view))
    }

    override func touchesEnded(_: Set<UITouch>, with _: UIEvent) {
        ended()
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent) {
        cancelled()
    }

    override func reset() {
        super.reset()
        holdTask?.cancel()
        holdTask = nil
        press = nil
        outcome = nil
        isOver = false
    }

    func began(at point: CGPoint) {
        // A second finger on the card is not a tap or a hold, and neither is a finger after the press was over.
        guard press == nil, !isOver else { return fail() }
        press = KeyboardPress(start: point, allowsHold: allowsHold)
        let delay = holdDelay
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.holdElapsed()
        }
    }

    func moved(to point: CGPoint) {
        press?.moved(to: point)
        settle()
    }

    func ended() {
        press?.ended()
        settle()
        fail()
    }

    /// The scroll view took the touch: a discrete recognizer that has not recognized can only fail.
    func cancelled() {
        fail()
    }

    private func holdElapsed() {
        guard state == .possible else { return }
        press?.holdElapsed()
        settle()
    }

    private func settle() {
        guard state == .possible, let press else { return }
        if press.isFailed {
            fail()
        } else if let result = press.outcome {
            outcome = result
            state = .ended
        }
    }

    /// The press is over (failed, or lifted): nothing it sees afterwards is recognized until UIKit calls `reset()`.
    private func fail() {
        holdTask?.cancel()
        press = nil
        isOver = true
        if state == .possible { state = .failed }
    }
}

/// `KeyboardPressRecognizer` on a SwiftUI card: `tap` on a tap, `hold` (when given) once the hold delay passes.
struct KeyboardCardPress: UIGestureRecognizerRepresentable {
    let tap: () -> Void
    var hold: (() -> Void)?

    func makeUIGestureRecognizer(context _: Context) -> KeyboardPressRecognizer {
        KeyboardPressRecognizer()
    }

    func updateUIGestureRecognizer(_ recognizer: KeyboardPressRecognizer, context _: Context) {
        recognizer.allowsHold = hold != nil
    }

    func handleUIGestureRecognizerAction(_ recognizer: KeyboardPressRecognizer, context _: Context) {
        guard recognizer.state == .ended else { return }
        switch recognizer.outcome {
        case .tap: tap()
        case .hold: hold?()
        case nil: break
        }
    }
}
