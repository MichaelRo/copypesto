// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// One clip on the keyboard, drawn as a thin face over `QuickInsertEntry` using `MobileShared` card components.
struct KeyboardClipKey: View {
    enum Feedback: Equatable {
        case inserted
        case copiedImage
    }

    let entry: QuickInsertEntry
    let cardSize: CGSize
    let feedback: Feedback?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.layoutDirection) private var environmentDirection
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.pestoAccent) private var accent
    @Environment(\.pestoAccentLabel) private var accentLabel
    @Environment(\.pestoSurface) private var surface

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CardGridLayout.cornerRadius, style: .continuous)
        let metrics = CardMetrics(width: cardSize.width, height: cardSize.height, typeSize: typeSize)
        let displayBody = entry.expandsOnInsert ? entry.insertionText() : entry.text
        let picture = entry.thumbnail.flatMap { KeyboardThumbnails.shared.picture(for: entry.id, data: $0) }
        let aspect = picture.map { Double($0.image.size.width / max($0.image.size.height, 1)) }
        let face = CardFace.decide(.init(
            type: entry.kind,
            text: displayBody,
            isConcealed: false,
            pictureAspect: aspect,
            isAnimated: entry.isAnimated,
            isDark: colorScheme == .dark
        ))
        let title = CardFace.faceTitle(
            type: entry.kind, inCollection: true, isConcealed: false,
            customTitle: entry.customTitle, ogTitle: entry.ogTitle
        )
        let cardDirection = Self.layoutDirection(for: entry.label()) ?? environmentDirection

        cardBody(face: face, picture: picture, displayBody: displayBody, title: title, metrics: metrics)
            .frame(width: cardSize.width, height: cardSize.height)
            .environment(\.layoutDirection, cardDirection)
            .background(colorScheme == .dark ? Color.white.opacity(0.10) : .white)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    feedback != nil ? accent : Color.primary.opacity(contrast == .increased ? 0.45 : 0.14),
                    lineWidth: feedback != nil ? 2 : 0.75
                )
            }
            .overlay(alignment: .topTrailing) {
                if entry.kind == .image, feedback == nil {
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption2.weight(.semibold))
                        .padding(5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .center) {
                if let feedback {
                    feedbackBadge(feedback)
                }
            }
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(Text(Self.accessibilityValue(of: entry)))
            .accessibilityHint(entry.kind == .image ? Text("Copies this picture") : Text("Inserts this clip"))
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func cardBody(
        face: CardFace, picture: KeyboardThumbnails.Picture?, displayBody: String, title: String?, metrics: CardMetrics
    )
    -> some View {
        let showsTitleOnFace = CardFace.showsCustomTitleOnFace(
            inCollection: true, isConcealed: false, customTitle: entry.customTitle
        )
        switch face {
        case let .picture(fills, _):
            pictureBody(picture: picture, fills: fills, title: title, showsTitleOnFace: showsTitleOnFace)
        case let .color(fill, ink):
            ColorCardFace(text: displayBody, fill: fill, ink: ink, metrics: metrics, title: title) {
                footLine(
                    ink: ink == .white ? .white : .black,
                    showsTitleOnFace: showsTitleOnFace
                )
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

    private func framed(
        title: String?, showsTitleOnFace: Bool, @ViewBuilder _ content: () -> some View
    )
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

    private func pictureBody(
        picture: KeyboardThumbnails.Picture?, fills: Bool, title: String?, showsTitleOnFace: Bool
    )
    -> some View {
        ZStack(alignment: .bottom) {
            if let picture {
                if fills {
                    Color.clear
                        .overlay { Image(uiImage: picture.image).resizable().scaledToFill() }
                        .clipped()
                } else {
                    ZStack {
                        // Blurred once when decoded (`KeyboardThumbnails`), not live on every frame of a scroll.
                        Color.clear
                            .overlay {
                                Image(uiImage: picture.backdrop ?? picture.image).resizable().scaledToFill()
                            }
                            .clipped()
                            .overlay(Color.black.opacity(0.35))
                        Image(uiImage: picture.image).resizable().scaledToFit()
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

    private func footLine(
        onPicture: Bool = false, ink: Color? = nil, showsTitleOnFace: Bool
    )
    -> some View {
        let age = CardAge.text(interval: Date.now.timeIntervalSince(entry.date))
        let symbol: String? = entry.sourceIsThisDevice
            ? CardFootLineView.device.symbol
            : (entry.fromAnotherDevice ? "laptopcomputer" : nil)
        let cleanTitle = entry.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let footTitle = (showsTitleOnFace || cleanTitle?.isEmpty != false) ? nil : cleanTitle
        let texts = CardMetaLine.candidates(
            .init(title: footTitle, source: entry.source, age: age, showsTitleOnFace: showsTitleOnFace)
        )
        let line = CardFootLine(symbol: symbol, texts: texts)
        let showsPin = CardMetaLine.showsPin(
            isPinned: entry.section == .pinned, isSnippet: entry.expandsOnInsert, hasShortcut: false
        )
        let trailingSymbol: String? = entry.expandsOnInsert
            ? "curlybraces"
            : (entry.hasRecognizedText ? "text.viewfinder" : nil)
        return CardFootLineView(
            line: line,
            isPinned: showsPin,
            onPicture: onPicture,
            ink: ink,
            showsGIF: entry.isAnimated,
            trailingSymbol: trailingSymbol
        )
    }

    private func feedbackBadge(_ feedback: Feedback) -> some View {
        let text: LocalizedStringKey = switch feedback {
        case .inserted: "Inserted \u{2713}"
        case .copiedImage: "Copied, paste it"
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accentLabel)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accent, in: Capsule())
            .padding(6)
    }

    private var accessibilityTitle: String {
        if entry.kind == .image {
            return entry.customTitle ?? entry.recognizedText ?? String(localized: "Picture")
        }
        return entry.label()
    }

    private static func accessibilityValue(of entry: QuickInsertEntry) -> String {
        let kind = entry.expandsOnInsert ? String(localized: "Snippet") : entry.kind.presentation.label
        return entry.fromAnotherDevice ? kind + ", " + String(localized: "from another device") : kind
    }

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
