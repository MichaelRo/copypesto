// SPDX-License-Identifier: MIT
import CoreGraphics

/// What `CardTreatment.decide` reads about a card. `isConcealed` is true for anything the card hides or has not shown
/// yet (a screen-share cover, a content-filter blur, a masked or sensitive clip, a clip not yet screened, a title being
/// renamed), and for those the answer is always the standard card.
/// `hasLinkMetadata` is a link with a title, a site name or an icon: it keeps its rich body.
public struct CardTreatmentInput: Sendable {
    /// `cardSize` is the card the picture is drawn on; without it the Mac's Medium card shape is assumed.
    public struct Picture: Sendable {
        public let aspectRatio: Double
        public let isAnimated: Bool
        public let isScreenCapture: Bool
        public let pixelSize: CGSize?
        public let cardSize: CGSize?

        public init(
            aspectRatio: Double, isAnimated: Bool, isScreenCapture: Bool = false, pixelSize: CGSize? = nil,
            cardSize: CGSize? = nil
        ) {
            self.aspectRatio = aspectRatio
            self.isAnimated = isAnimated
            self.isScreenCapture = isScreenCapture
            self.pixelSize = pixelSize
            self.cardSize = cardSize
        }

        public var fit: PictureFit {
            let cardAspect = cardSize.flatMap { $0.height > 0 ? Double($0.width / $0.height) : nil }
            return PictureFit.decide(
                aspectRatio: aspectRatio, isAnimated: isAnimated, isScreenCapture: isScreenCapture,
                cardAspect: cardAspect ?? PictureFit.referenceCardAspect, pixelSize: pixelSize, card: cardSize
            )
        }
    }

    public let type: ClipboardType
    public let text: String
    public let isConcealed: Bool
    public let picture: Picture?
    public let linkPictureShown: Bool
    public let hasLinkMetadata: Bool
    public let colorFill: HexColorComponents?
    public let backdropIsDark: Bool

    public init(
        type: ClipboardType, text: String, isConcealed: Bool, picture: Picture?, linkPictureShown: Bool,
        hasLinkMetadata: Bool, colorFill: HexColorComponents?, backdropIsDark: Bool
    ) {
        self.type = type
        self.text = text
        self.isConcealed = isConcealed
        self.picture = picture
        self.linkPictureShown = linkPictureShown
        self.hasLinkMetadata = hasLinkMetadata
        self.colorFill = colorFill
        self.backdropIsDark = backdropIsDark
    }
}
