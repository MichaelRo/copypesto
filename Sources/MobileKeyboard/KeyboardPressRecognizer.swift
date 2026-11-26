// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// A card's tap and hold as one UIKit recognizer. SwiftUI's `onTapGesture` and `onLongPressGesture` on every card held
/// a touch that started on a card until it had moved far enough, so reversing the row mid-glide felt stuck; this one
/// fails at the first movement past `KeyboardPress.slop` and when the scroll view cancels its touches.
final class KeyboardPressRecognizer: UIGestureRecognizer {
    var allowsHold = true
    private(set) var outcome: KeyboardPress.Outcome?
    private var press: KeyboardPress?
    private var holdTask: Task<Void, Never>?

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent) {
        guard touches.count == 1, press == nil, let touch = touches.first else {
            state = .failed
            return
        }
        press = KeyboardPress(start: touch.location(in: view), allowsHold: allowsHold)
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: KeyboardPress.holdDelay)
            guard !Task.isCancelled else { return }
            self?.holdElapsed()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent) {
        guard let touch = touches.first else { return }
        press?.moved(to: touch.location(in: view))
        settle()
    }

    override func touchesEnded(_: Set<UITouch>, with _: UIEvent) {
        press?.ended()
        settle()
        if state == .possible { state = .failed }
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        super.reset()
        holdTask?.cancel()
        holdTask = nil
        press = nil
        outcome = nil
    }

    private func holdElapsed() {
        guard state == .possible else { return }
        press?.holdElapsed()
        settle()
    }

    private func settle() {
        guard state == .possible, let press else { return }
        if press.isFailed {
            state = .failed
        } else if let result = press.outcome {
            outcome = result
            state = .ended
        }
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
