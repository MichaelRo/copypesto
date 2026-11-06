// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

struct HeaderOverlay {
    let ink: Color
    let scheme: ColorScheme
    let ageOpacity: Double

    static let onPicture = HeaderOverlay(ink: .white, scheme: .dark, ageOpacity: PictureScrim.ageOpacity)

    init(ink: Color, scheme: ColorScheme, ageOpacity: Double) {
        self.ink = ink
        self.scheme = scheme
        self.ageOpacity = ageOpacity
    }

    /// On a color the age is full ink: 85% of it falls under 4.5:1 on a mid-luminance fill.
    init(_ ink: CardInk) {
        self.init(ink: ink == .white ? .white : .black, scheme: ink == .white ? .dark : .light, ageOpacity: 1)
    }
}

@MainActor
extension ClipboardCard {
    // MARK: - Which treatment

    var treatment: CardTreatment {
        let text = switch item.type {
        case .text, .url: item.gridPreview
        default: ""
        }
        var picture: CardTreatmentInput.Picture?
        if item.type == .image, let shown = shownThumbnail, shown.image.size.height > 0 {
            picture = .init(
                aspectRatio: Double(shown.image.size.width / shown.image.size.height), isAnimated: shown.isAnimated
            )
        }
        return CardTreatment.decide(CardTreatmentInput(
            type: item.type,
            text: text,
            isConcealed: concealment.isConcealed || hidesItsContent || isRenamingTitle,
            picture: picture,
            linkPictureShown: urlOGImage != nil,
            hasLinkMetadata: item.ogTitle != nil || item.ogSiteName != nil || urlFavicon != nil,
            colorFill: item.type == .color ? ColorStringDetector.components(in: item.gridPreview) : nil,
            backdropIsDark: colorScheme == .dark
        ))
    }

    // MARK: - Picture and color cards

    func fullBleedPictureCard(fit: PictureFit, isAnimated: Bool) -> some View {
        ZStack(alignment: .top) {
            Color.white.opacity(0.06)
            pictureLayer(fit: fit)
                .padding(.top, fit == .fit ? CardLayout.headerHeight : 0)
            pictureScrim
            contentFirstChrome(over: .onPicture, onPicture: true, showsGIF: isAnimated, label: nil)
        }
    }

    func fullBleedColorCard(ink: CardInk) -> some View {
        let over = HeaderOverlay(ink)
        let label = CardPreviewText.display(item.gridPreview)
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8)
                .fill(detectedColor ?? Color.purple.opacity(0.5))
            contentFirstChrome(over: over, onPicture: false, showsGIF: false, label: label)
        }
    }

    @ViewBuilder
    private func pictureLayer(fit: PictureFit) -> some View {
        if let shown = shownThumbnail {
            let aspect = shown.image.size.height > 0 ? shown.image.size.width / shown.image.size.height : 1
            Color.clear
                .overlay {
                    if shown.isAnimated {
                        if fit == .fill {
                            AnimatedImageView(image: shown.image, animates: playsAnimations)
                                .aspectRatio(aspect, contentMode: .fill)
                        } else {
                            AnimatedImageView(image: shown.image, animates: playsAnimations)
                        }
                    } else {
                        Image(nsImage: shown.image)
                            .resizable()
                            .aspectRatio(contentMode: fit == .fill ? .fill : .fit)
                    }
                }
                .clipped()
        }
    }

    private var pictureScrim: some View {
        let solid = Double(CardLayout.headerHeight)
        let total = solid + PictureScrim.fadeHeight
        return LinearGradient(
            stops: [
                .init(color: .black.opacity(PictureScrim.topOpacity), location: 0),
                .init(color: .black.opacity(PictureScrim.topOpacity), location: solid / total),
                .init(color: .black.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: total)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private func contentFirstChrome(over: HeaderOverlay, onPicture: Bool, showsGIF: Bool, label: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(over: over)
            Spacer(minLength: 0)
            if let label {
                Text(label)
                    .scaledFont(size: CardInk.labelPoints(forLength: label.count), weight: .semibold, maxScale: 1.15)
                    .foregroundStyle(over.ink)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            contentFirstFooter(over: over, onPicture: onPicture, showsGIF: showsGIF)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
    }

    private func contentFirstFooter(over: HeaderOverlay, onPicture: Bool, showsGIF: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !item.tags.isEmpty {
                tagChipsRow(onDark: true)
            }
            HStack(alignment: .center, spacing: 6) {
                if let number = shortcutNumber {
                    ContentFirstPill(text: "\u{2318}\(number)", ink: over.ink, onPicture: onPicture)
                }
                if showsGIF {
                    ContentFirstPill(text: "GIF", ink: over.ink, onPicture: onPicture)
                }
                Spacer(minLength: 4)
                if item.pasteCount >= 2 {
                    ContentFirstPill(text: "\u{2191}\(item.pasteCount)", ink: over.ink, onPicture: onPicture)
                }
                if let collectionID = item.collectionID,
                   let collection = availableCollections.first(where: { $0.id == collectionID })
                {
                    contentFirstCollectionBadge(collection, ink: over.ink, onPicture: onPicture)
                }
            }
        }
        .environment(\.colorScheme, over.scheme)
    }

    /// The collection badge without the frosted ground the standard card gives it, which no contrast can be promised
    /// for over a picture: white on the pill ground there, the fill's own ink on a color.
    private func contentFirstCollectionBadge(_ collection: CollectionRef, ink: Color, onPicture: Bool) -> some View {
        HStack(spacing: 3) {
            CollectionIcon(symbolName: collection.symbolName)
                .font(.caption2.weight(.medium))
            Text(collection.name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(ink.opacity(PictureScrim.badgeOpacity))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            if onPicture { Capsule().fill(Color.black.opacity(PictureScrim.pillOpacity)) }
        }
    }

    // MARK: - Short text and links

    func largeTextBody(points: Double) -> some View {
        let shown = bodySize(CGFloat(points))
        let lines = CardTreatment.largeTextLineLimit(
            points: Double(shown) * Self.largeTextHeadroom,
            heightBudget: Double(CardLayout.textHeightBudget(for: cardDimensions))
        )
        return Text(CardPreviewText.display(item.gridPreview))
            .scaledFont(size: shown, weight: .semibold, maxScale: Self.largeTextHeadroom)
            .foregroundStyle(.primary.opacity(0.92))
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func hostFirstBody(_ link: LinkDisplay) -> some View {
        let roomy = CardLayout.textHeightBudget(for: cardDimensions) >= 90
        return VStack(alignment: .leading, spacing: 4) {
            Text(LinkDisplay.breakableHost(link.host))
                .scaledFont(
                    size: bodySize(CGFloat(LinkDisplay.hostPoints(forLength: link.host.count))),
                    weight: .semibold, maxScale: Self.largeTextHeadroom
                )
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(roomy ? 2 : 1)
                .truncationMode(.middle)
            if !link.rest.isEmpty {
                Text(link.rest)
                    .scaledFont(size: bodySize(11), maxScale: 1.3)
                    .pestoQuiet()
                    .lineLimit(roomy ? 3 : 2)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    static var largeTextHeadroom: Double {
        1.15
    }
}
