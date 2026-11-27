// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

struct CardInkOverlay {
    let ink: Color
    let scheme: ColorScheme
    let ageOpacity: Double

    static func onPicture(scheme: ColorScheme) -> CardInkOverlay {
        let ink = scheme == .dark
            ? (Color(hex: BrandPalette.parmesan) ?? .white)
            : (Color(hex: BrandPalette.mortar) ?? .black)
        return CardInkOverlay(ink: ink, scheme: scheme, ageOpacity: PictureScrim.ageOpacity)
    }

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
    var pictureOverlay: CardInkOverlay {
        CardInkOverlay.onPicture(scheme: colorScheme)
    }

    // MARK: - The foot glow (ADR 0068)

    /// Whether the card's foot glows: only a card drawn on its fill, never a picture, a color, a covered or a pending
    /// one. `GlassCardModifier` decides the color (the app's, or for an app with none, the theme's, muted).
    var showsFootGlow: Bool {
        guard concealment.allowsFootGlow, !item.analysisPending, item.type != .image else {
            return false
        }
        switch treatment {
        case .fullBleedPicture, .fullBleedColor: return false
        default: return true
        }
    }

    var footGlowColorHex: String? {
        item.isRemote ? nil : item.sourceDominantColorHex
    }

    // MARK: - Which treatment

    var treatment: CardTreatment {
        let text = switch item.type {
        case .text, .url: item.gridPreview
        default: ""
        }
        var picture: CardTreatmentInput.Picture?
        if item.type == .image, let shown = shownThumbnail, let aspect = pictureAspect(shown.image) {
            picture = .init(
                aspectRatio: aspect, isAnimated: shown.isAnimated,
                isScreenCapture: ScreenCaptureApps.isCapture(sourceBundleID: item.sourceBundleID),
                pixelSize: item.pixelSize, cardSize: cardDimensions
            )
        }
        return CardTreatment.decide(CardTreatmentInput(
            type: item.type,
            text: text,
            isConcealed: concealment.isConcealed || hidesItsContent || isRenamingTitle,
            picture: picture,
            linkPictureShown: urlOGImage != nil,
            hasLinkMetadata: trimmedOgTitle != nil || item.ogSiteName != nil || urlFavicon != nil,
            colorFill: item.type == .color ? ColorStringDetector.wholeComponents(in: item.gridPreview) : nil,
            backdropIsDark: colorScheme == .dark
        ))
    }

    // MARK: - Picture and color cards

    func fullBleedPictureCard(fit: PictureFit, isAnimated: Bool) -> some View {
        let over = pictureOverlay
        return ZStack(alignment: .top) {
            surface
            if fit == .fit, let shown = shownThumbnail {
                pictureBackdrop(shown.image)
            }
            pictureLayer(fit: fit)
            contentFirstChrome(
                MetaLineStyle(over: over, onPicture: true, showsGIF: isAnimated),
                title: trimmedCustomTitle,
                label: nil
            )
        }
    }

    var fullBleedLinkChromeTitle: String? {
        trimmedCustomTitle
    }

    var fullBleedLinkCard: some View {
        let over = pictureOverlay
        return ZStack(alignment: .top) {
            surface
            urlImageBody
            contentFirstChrome(
                MetaLineStyle(over: over, onPicture: true, showsGIF: urlOGImageIsAnimated),
                title: fullBleedLinkChromeTitle,
                label: nil
            )
        }
    }

    func fullBleedColorCard(ink: CardInk) -> some View {
        let over = CardInkOverlay(ink)
        let label = CardPreviewText.display(item.gridPreview)
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8)
                .fill(detectedColor ?? Color.purple.opacity(0.5))
            contentFirstChrome(MetaLineStyle(over: over), title: trimmedCustomTitle, label: label)
        }
    }

    /// The stored pixel size first (the picture's own shape), the thumbnail's when the clip has none.
    private func pictureAspect(_ image: NSImage) -> Double? {
        if let size = item.pixelSize { return Double(size.width / size.height) }
        return image.size.height > 0 ? Double(image.size.width / image.size.height) : nil
    }

    /// The band a fitted picture clears: the line of facts, and a title's chip above it.
    private var pictureFooterBand: CGFloat {
        CardLayout.footerReserve + (trimmedCustomTitle == nil ? 0 : 20)
    }

    @ViewBuilder
    private func pictureLayer(fit: PictureFit) -> some View {
        if let shown = shownThumbnail {
            let aspect = pictureAspect(shown.image) ?? 1
            switch fit {
            case .fill, .fillFromTop:
                Color.clear
                    .overlay(alignment: fit == .fillFromTop ? .top : .center) {
                        pictureImage(shown, aspect: aspect, contentMode: .fill)
                    }
                    .clipped()
            case .fit:
                let band = pictureFooterBand
                let pixels = item.pixelSize
                let placement = PictureFrameLayout { size in
                    PictureFrame.fitted(aspectRatio: aspect, in: size, footerBand: band, pixelSize: pixels)
                }
                placement {
                    pictureImage(shown, aspect: aspect, contentMode: .fill)
                }
            }
        }
    }

    @ViewBuilder
    private func pictureImage(
        _ shown: (image: NSImage, isAnimated: Bool), aspect: Double, contentMode: ContentMode
    )
    -> some View {
        if shown.isAnimated {
            AnimatedImageView(image: shown.image, animates: playsAnimations, aspectFit: contentMode == .fit)
                .aspectRatio(aspect, contentMode: contentMode)
        } else if item.pixelSize.map(PictureFrame.drawsPixelsSharp) == true {
            Image(nsImage: shown.image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(aspect, contentMode: contentMode)
        } else {
            Image(nsImage: shown.image)
                .resizable()
                .aspectRatio(aspect, contentMode: contentMode)
        }
    }

    private func pictureBackdrop(_ image: NSImage) -> some View {
        Color.clear
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 14, opaque: true)
            }
            .overlay(Color.black.opacity(0.35))
            .clipped()
    }

    private func contentFirstChrome(_ style: MetaLineStyle, title: String?, label: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            if style.onPicture, let title, let over = style.over {
                renameableTitleChip {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(over.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            surface.opacity(PictureScrim.pillOpacity),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.32), lineWidth: 1)
                        }
                        .environment(\.colorScheme, over.scheme)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
            if let label, let over = style.over {
                if let title {
                    renameableTitleChip {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(over.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
                }
                Text(label)
                    .scaledFont(size: CardInk.labelPoints(forLength: label.count), weight: .semibold, maxScale: 1.15)
                    .foregroundStyle(over.ink)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            metaLine(style)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Short text and links

    func largeTextBody(points: Double) -> some View {
        let shown = bodySize(CGFloat(points))
        let hasTitle = hasTopTitleSlot
        let spaceAboveCaps = Self.spaceAboveCaps(size: shown, weight: .semibold)
        let extra = hasTitle ? 0 : CardLayout.largeTextTopPadding(spaceAboveCaps: spaceAboveCaps)
        let lines = CardTreatment.largeTextLineLimit(
            points: Double(shown),
            heightBudget: Double(CardLayout.textHeightBudget(for: cardDimensions, hasTitle: hasTitle) - extra),
            maxLines: CardTreatment.maxLines(forPoints: points)
        )
        return Text(CardPreviewText.display(item.gridPreview))
            .scaledFont(size: shown, weight: .semibold, maxScale: Self.largeTextHeadroom)
            .foregroundStyle(.primary.opacity(0.92))
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, extra)
    }

    func hostFirstBody(_ link: LinkDisplay) -> some View {
        let hostPoints = bodySize(CGFloat(LinkDisplay.hostPoints(forLength: link.host.count)))
        let pathPoints = bodySize(11)
        let hasTitle = hasTopTitleSlot
        let extra = hasTitle ? 0 : CardLayout.largeTextTopPadding(spaceAboveCaps: Self.spaceAboveCaps(
            size: hostPoints,
            weight: .semibold
        ))
        let pathLines = LinkDisplay.pathLineLimit(
            hostPoints: Double(hostPoints),
            pathPoints: Double(pathPoints),
            heightBudget: Double(CardLayout.textHeightBudget(for: cardDimensions, hasTitle: hasTitle) - extra)
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(link.host)
                .scaledFont(size: hostPoints, weight: .semibold, maxScale: Self.largeTextHeadroom)
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(LinkDisplay.hostMinimumScale)
                .truncationMode(.tail)
            if !link.rest.isEmpty, pathLines > 0 {
                Text(link.rest)
                    .scaledFont(size: pathPoints, maxScale: 1.0)
                    .pestoQuiet()
                    .lineLimit(pathLines)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, extra)
    }

    /// The gap between the top of a first line's box and the top of its capital letters, from the font itself.
    private static func spaceAboveCaps(size: CGFloat, weight: Font.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight == .semibold ? .semibold : .regular)
        return max(0, font.ascender - font.capHeight)
    }

    /// Fixed sizes grow with the card, never with the text-size setting: the step would overflow a fixed card.
    static var largeTextHeadroom: Double {
        1.0
    }
}
