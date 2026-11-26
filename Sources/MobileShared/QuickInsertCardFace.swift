// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// A clip of the quick-insert set drawn as Pesto's card (ADR 0074): the card's white (white at 10 percent in dark) with
/// its hairline, the face `CardFace` decides, the foot glow in the app's color (ADR 0068) and one foot line led by the
/// app's icon. The keyboard, the AutoFill picker and the keyboard's size preview all draw this one card.
struct QuickInsertCardFace: View {
    let entry: QuickInsertEntry
    let size: CGSize
    let theme: WidgetSnapshot.Theme
    var appIcon: Data?
    /// A title is shown on the face as it is in a collection; the AutoFill picker's All list leaves it to the foot.
    var inCollection = true
    var picture: UIImage?
    var backdrop: UIImage?
    var hasShadow = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.layoutDirection) private var environmentDirection
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.pestoSurface) private var surface

    static let shape = RoundedRectangle(cornerRadius: CardGridLayout.cornerRadius, style: .continuous)

    var body: some View {
        let metrics = CardMetrics(width: size.width, height: size.height, typeSize: typeSize)
        let displayBody = Self.displayBody(of: entry)
        let aspect = picture.map { Double($0.size.width / max($0.size.height, 1)) }
        let face = CardFace.decide(.init(
            type: entry.kind,
            text: displayBody,
            isConcealed: false,
            pictureAspect: aspect,
            isAnimated: entry.isAnimated,
            isDark: colorScheme == .dark
        ))
        let title = CardFace.faceTitle(
            type: entry.kind, inCollection: inCollection, isConcealed: false,
            customTitle: entry.customTitle, ogTitle: entry.ogTitle
        )
        let showsTitleOnFace = CardFace.showsCustomTitleOnFace(
            inCollection: inCollection, isConcealed: false, customTitle: entry.customTitle
        )
        let cardDirection = Self.layoutDirection(for: entry.label()) ?? environmentDirection

        cardBody(
            face: face,
            displayBody: displayBody,
            title: title,
            showsTitleOnFace: showsTitleOnFace,
            metrics: metrics
        )
        .frame(width: size.width, height: size.height)
        .environment(\.layoutDirection, cardDirection)
        .background {
            ZStack {
                colorScheme == .dark ? Color.white.opacity(0.10) : .white
                if CardGlowLayer.shows(on: face) { CardGlowLayer(glow: glow, reach: glowReach) }
            }
            .clipShape(Self.shape)
            .shadow(
                color: hasShadow ? .black.opacity(colorScheme == .dark ? 0.22 : 0.07) : .clear, radius: 3, y: 1
            )
        }
        .clipShape(Self.shape)
        .overlay {
            Self.shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.45 : 0.14), lineWidth: 0.75)
        }
    }

    /// A snippet that needs nothing from the person shows what it will insert; one that asks shows its template.
    static func displayBody(of entry: QuickInsertEntry) -> String {
        entry.expandsOnInsert && TemplateExpander.fillsWithoutAsking(entry.text) ? entry.insertionText() : entry.text
    }

    /// The glow's stops are set for a card of the app's shape; on the keyboard's short card 40 percent of the height
    /// is too little to read, so they stretch.
    private var glowReach: Double {
        size.height < 140 ? 1.5 : 1
    }

    private var glow: CardGlow? {
        let isDark = colorScheme == .dark
        return CardGlow.decide(
            colorHex: entry.sourceColorHex, themeAccentHex: theme.accent(dark: isDark), isDark: isDark,
            isGlass: false, increaseContrast: contrast == .increased, isSelected: false
        )
    }

    @ViewBuilder
    private func cardBody(
        face: CardFace, displayBody: String, title: String?, showsTitleOnFace: Bool, metrics: CardMetrics
    )
    -> some View {
        switch face {
        case let .picture(fills, _):
            pictureBody(fills: fills, title: title, showsTitleOnFace: showsTitleOnFace)
        case let .color(fill, ink):
            ColorCardFace(text: displayBody, fill: fill, ink: ink, metrics: metrics, title: title) {
                footLine(ink: ink == .white ? .white : .black, showsTitleOnFace: showsTitleOnFace)
            }
        case let .largeText(points):
            framed(title: title, showsTitleOnFace: showsTitleOnFace) {
                LargeTextBody(text: CardPreviewText.display(displayBody), points: points, metrics: metrics)
            }
        case let .link(link):
            framed(title: title, showsTitleOnFace: showsTitleOnFace) {
                LinkBody(link: link, metrics: metrics, hasTitle: title != nil)
            }
        case .code:
            framed(title: title, showsTitleOnFace: showsTitleOnFace) {
                PlainTextBody(text: displayBody, isCode: true, metrics: metrics, hasTitle: title != nil)
            }
        case .text, .covered, .shownSecret, .linkPicture, .file:
            framed(title: title, showsTitleOnFace: showsTitleOnFace) {
                PlainTextBody(text: displayBody, isCode: false, metrics: metrics, hasTitle: title != nil)
            }
        }
    }

    private func framed(title: String?, showsTitleOnFace: Bool, @ViewBuilder _ content: () -> some View)
    -> some View {
        VStack(alignment: .leading, spacing: CardMetrics.footGap) {
            VStack(alignment: .leading, spacing: CardMetrics.titleGap) {
                if let title {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footLine(showsTitleOnFace: showsTitleOnFace)
        }
        .padding(CardMetrics.inset)
    }

    private func pictureBody(fills: Bool, title: String?, showsTitleOnFace: Bool) -> some View {
        ZStack(alignment: .bottom) {
            if let picture {
                if fills {
                    Color.clear
                        .overlay { Image(uiImage: picture).resizable().scaledToFill() }
                        .clipped()
                } else {
                    ZStack {
                        // Blurred once when decoded (`KeyboardThumbnails`), not live on every frame of a scroll.
                        Color.clear
                            .overlay { Image(uiImage: backdrop ?? picture).resizable().scaledToFill() }
                            .clipped()
                            .overlay(Color.black.opacity(0.35))
                        Image(uiImage: picture).resizable().scaledToFit()
                            .padding(.bottom, title == nil ? 28 : 48)
                    }
                }
            } else {
                Color.secondary.opacity(0.10)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(surface.opacity(PictureScrim.pillOpacity), in: .capsule)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                }
                footLine(onPicture: true, showsTitleOnFace: showsTitleOnFace)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private func footLine(onPicture: Bool = false, ink: Color? = nil, showsTitleOnFace: Bool) -> some View {
        let age = CardAge.text(interval: Date.now.timeIntervalSince(entry.date))
        let symbol: String? = entry.sourceIsThisDevice
            ? CardFootLineView.device.symbol
            : (entry.fromAnotherDevice ? "laptopcomputer" : nil)
        let cleanTitle = entry.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let footTitle = (showsTitleOnFace || cleanTitle?.isEmpty != false) ? nil : cleanTitle
        let texts = CardMetaLine.candidates(
            .init(title: footTitle, source: entry.source, age: age, showsTitleOnFace: showsTitleOnFace)
        )
        let showsPin = CardMetaLine.showsPin(
            isPinned: entry.section == .pinned, isSnippet: entry.expandsOnInsert, hasShortcut: false
        )
        let trailingSymbol: String? = entry.expandsOnInsert
            ? "curlybraces"
            : (entry.hasRecognizedText ? "text.viewfinder" : nil)
        return CardFootLineView(
            line: CardFootLine(symbol: symbol, texts: texts),
            isPinned: showsPin,
            onPicture: onPicture,
            ink: ink,
            showsGIF: entry.isAnimated,
            trailingSymbol: trailingSymbol,
            appIcon: appIcon.flatMap { AppIconImages.image(for: entry.sourceBundleID, data: $0) }
        )
    }

    /// The direction a card's text reads in: its first strong letter decides, so a Hebrew clip reads right to left on
    /// an English keyboard.
    static func layoutDirection(for text: String) -> LayoutDirection? {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x0590...0x08FF).contains(value)
                || (0xFB1D...0xFDFF).contains(value)
                || (0xFE70...0xFEFF).contains(value)
            {
                return .rightToLeft
            }
            if scalar.properties.isAlphabetic {
                return .leftToRight
            }
        }
        return nil
    }
}
