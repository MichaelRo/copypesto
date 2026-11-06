// SPDX-License-Identifier: MIT

public enum CardTreatment: Equatable, Sendable {
    case standard
    case fullBleedPicture(PictureFit, isAnimated: Bool)
    case fullBleedColor(CardInk)
    case largeText(points: Double)
    case hostFirstLink(LinkDisplay)

    public static let shortTextLimit = 48
    public static let lineHeightFactor = 1.25
    public static let headlineLimit = 24
    public static let headlinePoints = 24.0
    public static let secondaryPoints = 18.0
    private static let headlineMaxLines = 2
    private static let secondaryMaxLines = 3

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
            guard !input.linkPictureShown, !input.hasLinkMetadata,
                  let link = LinkDisplay.parse(input.text) else { return .standard }
            return .hostFirstLink(link)
        case .code, .file:
            return .standard
        }
    }

    /// Fixed sizes by length, never fitted to a measurement: 24 pt up to 24 characters, 18 pt up to 48.
    private static let pointsMemo = StringMemo<Double?>()

    private static func largeTextPoints(for raw: String) -> Double? {
        pointsMemo.value(for: raw) { computeLargeTextPoints(for: raw) }
    }

    private static func computeLargeTextPoints(for raw: String) -> Double? {
        let text = CardPreviewText.display(raw)
        guard !text.isEmpty, !text.contains("\n"), text.count <= shortTextLimit,
              !CardPreviewText.isSingleGlyph(text) else { return nil }
        return text.count <= headlineLimit ? headlinePoints : secondaryPoints
    }

    public static func maxLines(forPoints points: Double) -> Int {
        points >= headlinePoints ? headlineMaxLines : secondaryMaxLines
    }

    /// How many lines of `points` type (as drawn, already scaled to the card) fit the height left between header and
    /// footer, from one up to `maxLines`, which belongs to the step's base size.
    public static func largeTextLineLimit(points: Double, heightBudget: Double, maxLines: Int) -> Int {
        let fits = Int(heightBudget / (points * lineHeightFactor))
        return min(max(fits, 1), maxLines)
    }
}
