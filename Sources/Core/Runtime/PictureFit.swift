// SPDX-License-Identifier: MIT

/// Whether a picture card crops the picture to fill the card or shows all of it. A card is about as wide as it is
/// tall, so anything much wider or taller than that loses a third of its words or more when filled (a 3:2 boarding
/// pass lost "G" of GATE); those are shown whole.
public enum PictureFit: Equatable, Sendable {
    case fill
    case fit

    public static let fillRange: ClosedRange<Double> = 0.8...1.35

    public static func decide(aspectRatio: Double) -> PictureFit {
        aspectRatio.isFinite && fillRange.contains(aspectRatio) ? .fill : .fit
    }
}
