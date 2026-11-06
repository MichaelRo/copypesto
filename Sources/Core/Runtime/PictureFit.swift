// SPDX-License-Identifier: MIT

/// Whether a picture card crops the picture to fill the card or shows all of it. A card is about as wide as it is
/// tall, so a very tall screenshot or a very wide banner filled to it would be a thin unreadable slice of the middle.
public enum PictureFit: Equatable, Sendable {
    case fill
    case fit

    public static let fillRange: ClosedRange<Double> = 0.6...2.0

    public static func decide(aspectRatio: Double) -> PictureFit {
        aspectRatio.isFinite && fillRange.contains(aspectRatio) ? .fill : .fit
    }
}
