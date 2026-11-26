// SPDX-License-Identifier: MIT
import CoreGraphics

/// Whether a picture card crops the picture to fill the card or shows all of it (ADR 0041, ADR 0080). A card is about
/// as wide as it is tall, so anything much wider or taller than that loses a third of its words or more when filled (a
/// 3:2 boarding pass lost "G" of GATE); those are shown whole. The ranges are measured against the card's own shape, so
/// the wide keyboard card fills a 16:9 photo and fits a square one.
public enum PictureFit: Equatable, Sendable {
    case fill
    /// A very tall picture (a receipt, a whole web page) shown whole is a sliver; its top is what names it.
    case fillFromTop
    case fit

    public var fills: Bool {
        self != .fit
    }

    /// The Mac's Medium card (180 × 160), the shape the absolute ranges below were drawn for.
    public static let referenceCardAspect = 1.125
    public static let fillRange: ClosedRange<Double> = 0.8...1.35
    public static let animatedFillRange: ClosedRange<Double> = 0.55...1.85
    /// A screen capture carries words to its edges, so it fills only when that crops a tenth of it or less.
    public static let screenCaptureCrop = 0.1
    /// Below this, at the reference shape, a picture fills from its top instead of standing as a sliver.
    public static let fillFromTopBelow = 0.4

    public static func decide(
        aspectRatio: Double,
        isAnimated: Bool = false,
        isScreenCapture: Bool = false,
        cardAspect: Double = referenceCardAspect,
        pixelSize: CGSize? = nil,
        card: CGSize? = nil
    )
    -> PictureFit {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return .fit }
        let shape = cardAspect.isFinite && cardAspect > 0 ? cardAspect : referenceCardAspect
        if let pixelSize, let card, isSmall(pixelSize, on: card) { return .fit }
        let relative = aspectRatio / shape
        if relative < fillFromTopBelow / referenceCardAspect { return .fillFromTop }
        if isScreenCapture, !isAnimated {
            let band = (1 - screenCaptureCrop)...(1 / (1 - screenCaptureCrop))
            return band.contains(relative) ? .fill : .fit
        }
        let range = isAnimated ? animatedFillRange : fillRange
        let scaled = (range.lowerBound / referenceCardAspect)...(range.upperBound / referenceCardAspect)
        return scaled.contains(relative) ? .fill : .fit
    }

    /// Smaller than the card: an icon or a sprite would only blur when stretched across it.
    public static func isSmall(_ pixelSize: CGSize, on card: CGSize) -> Bool {
        max(pixelSize.width, pixelSize.height) < min(card.width, card.height)
    }
}
