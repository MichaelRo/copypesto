// SPDX-License-Identifier: MIT
import CoreGraphics

/// The text on a card grows and shrinks with the card-size setting: the medium card (200 points wide) is the baseline,
/// the large one (240) draws text a fifth larger, and a small one (160) a little smaller, never below what reads.
public enum CardTextScale {
    public static let baselineWidth: CGFloat = 200
    public static let range: ClosedRange<CGFloat> = 0.85...1.2

    public static func factor(forWidth width: CGFloat) -> CGFloat {
        min(max(width / baselineWidth, range.lowerBound), range.upperBound)
    }

    public static func size(_ base: CGFloat, cardWidth width: CGFloat) -> CGFloat {
        base * factor(forWidth: width)
    }

    /// The height one line of body text takes, for working out how many lines fit.
    public static func lineHeight(cardWidth width: CGFloat) -> CGFloat {
        18 * factor(forWidth: width)
    }
}
