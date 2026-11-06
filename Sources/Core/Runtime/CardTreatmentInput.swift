// SPDX-License-Identifier: MIT

/// What `CardTreatment.decide` reads about a card. `isConcealed` is true for anything the card hides or has not shown
/// yet (a screen-share cover, a content-filter blur, a masked or sensitive clip, a clip not yet screened, a title being
/// renamed), and for those the answer is always the standard card.
/// `hasLinkMetadata` is a link with a title, a site name or an icon: it keeps its rich body.
public struct CardTreatmentInput: Sendable {
    public struct Picture: Sendable {
        public let aspectRatio: Double
        public let isAnimated: Bool

        public init(aspectRatio: Double, isAnimated: Bool) {
            self.aspectRatio = aspectRatio
            self.isAnimated = isAnimated
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
