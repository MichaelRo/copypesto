// SPDX-License-Identifier: MIT
import SwiftUI

/// A short sideways shake, like the macOS password field refusing a wrong password. Raise `progress` by one inside a
/// `Motion.animation` to play it once; under Reduce Motion that animation is nil and nothing moves.
struct ShakeEffect: GeometryEffect {
    static let travel: CGFloat = 6
    static let shakes: CGFloat = 3

    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Zero at every whole number, so a shake always ends where it began.
    static func offset(at progress: CGFloat) -> CGFloat {
        travel * sin(progress * .pi * 2 * shakes)
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: Self.offset(at: progress), y: 0))
    }
}
