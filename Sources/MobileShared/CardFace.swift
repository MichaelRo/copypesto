// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

enum CardFace: Equatable {
    case covered(isSecret: Bool)
    case shownSecret
    case picture(fillsCard: Bool, isAnimated: Bool)
    case linkPicture
    case color(HexColorComponents, ink: CardInk)
    case largeText(points: Double)
    case link(LinkDisplay)
    case code
    case file
    case text

    struct Input {
        var type: ClipboardType
        var text: String
        var isConcealed: Bool
        var isSecret = false
        var pictureAspect: Double?
        var isAnimated = false
        var hasLinkPicture = false
        var isDark = false
    }

    /// ADR 0041: a picture fills the card only near the card's own shape; anything else is shown whole.
    static let fillRange = CardTreatment.pictureFillRange

    static func decide(_ input: Input) -> CardFace {
        if input.isConcealed { return .covered(isSecret: input.isSecret) }
        if input.isSecret { return .shownSecret }
        let colorFill = input.type == .color ? ColorLiteralParser.firstColor(in: input.text) : nil
        let treatment = CardTreatment.decide(CardTreatmentInput(
            type: input.type,
            text: input.text,
            isConcealed: false,
            picture: input.pictureAspect.map { .init(aspectRatio: $0, isAnimated: input.isAnimated) },
            linkPictureShown: input.hasLinkPicture,
            hasLinkMetadata: false,
            colorFill: colorFill,
            backdropIsDark: input.isDark
        ))
        switch treatment {
        case let .fullBleedPicture(fit, isAnimated):
            if isAnimated, let aspect = input.pictureAspect {
                let gifFit = PictureFit.decide(aspectRatio: aspect, isAnimated: true)
                return .picture(fillsCard: gifFit == .fill, isAnimated: true)
            }
            return .picture(fillsCard: fit == .fill, isAnimated: isAnimated)
        case let .fullBleedColor(ink):
            return colorFill.map { .color($0, ink: ink) } ?? .text
        case let .largeText(points):
            return .largeText(points: points)
        case let .hostFirstLink(link):
            return .link(link)
        case .standard:
            return standard(input)
        }
    }

    private static func standard(_ input: Input) -> CardFace {
        switch input.type {
        case .image: .picture(fillsCard: false, isAnimated: input.isAnimated)
        case .url: input.hasLinkPicture ? .linkPicture : .text
        case .code: .code
        case .file: .file
        case .text, .color: .text
        }
    }

    /// Every non-concealed clip with a custom title shows it on its card face (`All`, `Pinned`, and collections);
    /// a link without a custom title also shows its page title.
    static func faceTitle(
        type: ClipboardType,
        inCollection _: Bool,
        isConcealed: Bool,
        customTitle: String?,
        ogTitle: String?
    )
    -> String? {
        guard !isConcealed else { return nil }
        if let custom = trimmed(customTitle) { return custom }
        if type == .url, let page = trimmed(ogTitle) { return page }
        return nil
    }

    static func showsCustomTitleOnFace(inCollection _: Bool, isConcealed: Bool, customTitle: String?) -> Bool {
        !isConcealed && trimmed(customTitle) != nil
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
