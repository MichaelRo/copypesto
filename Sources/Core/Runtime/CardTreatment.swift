// SPDX-License-Identifier: MIT

public enum CardTreatment: Equatable, Sendable {
    case standard
    case fullBleedPicture(PictureFit, isAnimated: Bool)
    case fullBleedColor(CardInk)
    case largeText(points: Double)
    case hostFirstLink(LinkDisplay)

    public static let shortTextLimit = 48
    public static let lineHeightFactor = 1.25
    public static let maxLargeTextLines = 3

    public static func decide(_ input: CardTreatmentInput) -> CardTreatment {
        guard !input.isConcealed else { return .standard }
        switch input.type {
        case .image:
            guard let picture = input.picture else { return .standard }
            return .fullBleedPicture(
                PictureFit.decide(aspectRatio: picture.aspectRatio),
                isAnimated: picture.isAnimated
            )
        case .color:
            guard let fill = input.colorFill else { return .standard }
            return .fullBleedColor(CardInk.forFill(fill, backdropIsDark: input.backdropIsDark))
        case .text:
            return largeTextPoints(for: input.text).map { .largeText(points: $0) } ?? .standard
        case .url:
            guard !input.linkPictureShown, let link = LinkDisplay.parse(input.text) else { return .standard }
            return .hostFirstLink(link)
        case .code, .file:
            return .standard
        }
    }

    /// Fixed sizes by length, never fitted to a measurement: 24 pt up to 16 characters, 20 up to 32, 17 up to 48.
    private static func largeTextPoints(for raw: String) -> Double? {
        let text = CardPreviewText.display(raw)
        guard !text.isEmpty, !text.contains("\n"), text.count <= shortTextLimit,
              !CardPreviewText.isSingleGlyph(text) else { return nil }
        switch text.count {
        case ...16: return 24
        case ...32: return 20
        default: return 17
        }
    }

    /// How many lines of `points` type fit the height left between header and footer, from one up to three.
    public static func largeTextLineLimit(points: Double, heightBudget: Double) -> Int {
        let fits = Int(heightBudget / (points * lineHeightFactor))
        return min(max(fits, 1), maxLargeTextLines)
    }
}
