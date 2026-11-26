// SPDX-License-Identifier: MIT
import CoreGraphics

/// What one touch on a keyboard card means: a tap, a hold (the other way to insert), or neither because the person is
/// scrolling the row. It fails as soon as the finger moves past `slop`, so the scroll view's pan never waits on it.
struct KeyboardPress {
    enum Outcome: Equatable {
        case tap
        case hold
    }

    static let slop: CGFloat = 10
    static let holdDelay: Duration = .milliseconds(400)

    let start: CGPoint
    let allowsHold: Bool
    private(set) var outcome: Outcome?
    private(set) var isFailed = false

    init(start: CGPoint, allowsHold: Bool) {
        self.start = start
        self.allowsHold = allowsHold
    }

    mutating func moved(to point: CGPoint) {
        guard outcome == nil, !isFailed else { return }
        if hypot(point.x - start.x, point.y - start.y) > Self.slop { isFailed = true }
    }

    mutating func holdElapsed() {
        guard outcome == nil, !isFailed else { return }
        if allowsHold {
            outcome = .hold
        } else {
            isFailed = true
        }
    }

    mutating func ended() {
        guard outcome == nil, !isFailed else { return }
        outcome = .tap
    }
}
