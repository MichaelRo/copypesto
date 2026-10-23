// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Every animation goes through here so Reduce Motion is honoured in one place. A state change with no animation still
/// happens; it just doesn't move.
@MainActor
enum Motion {
    /// Tests set this; production code never does (same pattern as `reduceTransparencyOverride`).
    static var reduceMotionOverride: Bool?

    static var reduceMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func animation(_ animation: Animation = .default) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// The four durations new motion uses, so Pesto's animations read as one family: a quick change of state, something
/// moving or entering the layout, a colour or tint change, and a confirmation that lands. Pictures keep the settle
/// springs in `SettleOnAppear`; the shelf's own slide is `PanelMotion`. Use them as
/// `.animation(Motion.animation(.pestoQuick), value: x)`.
extension Animation {
    static let pestoQuick = Animation.easeOut(duration: 0.15)
    static let pestoMove = Animation.snappy(duration: 0.22)
    static let pestoWash = Animation.smooth(duration: 0.4)
    static let pestoPop = Animation.spring(response: 0.3, dampingFraction: 0.6)
}
