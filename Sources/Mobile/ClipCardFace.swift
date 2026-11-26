// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// `revision` is a stored value so the face is drawn again when the storage actor changes the clip: a change merged
/// into this context does not notify the views that read the model, and every other input here would compare equal.
struct ClipCardFace: View {
    let item: ClipboardItem
    let face: CardFace
    let media: CardMediaState
    let width: CGFloat
    let revision: ClipCard.Revision
    var playsAnimation = false
    var inCollection = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isConcealed: Bool {
        if case .covered = face { return true }
        return false
    }

    private var faceTitle: String? {
        CardFace.faceTitle(
            type: item.type,
            inCollection: inCollection,
            isConcealed: isConcealed,
            customTitle: item.customTitle,
            ogTitle: item.ogTitle
        )
    }

    private var showsCustomTitleOnFace: Bool {
        CardFace.showsCustomTitleOnFace(
            inCollection: inCollection,
            isConcealed: isConcealed,
            customTitle: item.customTitle
        )
    }

    var body: some View {
        let metrics = CardMetrics(width: width, typeSize: typeSize)
        let title = faceTitle
        let showsTitleInBody = title != nil
        switch face {
        case let .covered(isSecret):
            CoveredCardFace(item: item, isSecret: isSecret)
        case .shownSecret:
            framed(title: title) {
                SecretShownBody(item: item, text: media.revealedText, metrics: metrics, hasTitle: showsTitleInBody)
            }
        case let .picture(fit, isAnimated):
            PictureCardFace(
                image: media.picture?.image, fit: fit, pixelSize: item.pixelSize,
                animation: playsAnimation ? media.picture?.animation : nil,
                title: title
            ) {
                ItemFootLineView(
                    item: item, onPicture: true, showsGIF: isAnimated, showsTitleOnFace: showsCustomTitleOnFace
                )
            }
        case .linkPicture:
            let linkText = CardPreviewText.display(item.gridPreview).trimmingCharacters(in: .whitespacesAndNewlines)
            let linkSubtitle = LinkDisplay.parse(item.gridPreview)?.host ?? (linkText.isEmpty ? nil : linkText)
            PictureCardFace(
                image: media.linkPicture,
                fit: .fill,
                animation: playsAnimation ? media.linkAnimation : nil,
                title: title,
                subtitle: linkSubtitle
            ) {
                ItemFootLineView(
                    item: item,
                    onPicture: true,
                    showsGIF: media.isLinkAnimated,
                    showsTitleOnFace: showsCustomTitleOnFace
                )
            }
        case let .color(fill, ink):
            ColorCardFace(
                text: item.gridPreview, fill: fill, ink: ink, metrics: metrics, title: title
            ) {
                ItemFootLineView(
                    item: item, ink: ink == .white ? .white : .black, showsTitleOnFace: showsCustomTitleOnFace
                )
            }
        case let .largeText(points):
            framed(title: title) {
                LargeTextBody(text: CardPreviewText.display(item.gridPreview), points: points, metrics: metrics)
            }
        case let .link(link):
            framed(title: title) { LinkBody(link: link, metrics: metrics, hasTitle: showsTitleInBody) }
        case .code:
            framed(title: title) {
                PlainTextBody(text: item.gridPreview, isCode: true, metrics: metrics, hasTitle: showsTitleInBody)
            }
        case .file:
            framed(title: title) { FileBody(preview: item.gridPreview, hasTitle: showsTitleInBody) }
        case .text:
            framed(title: title) {
                PlainTextBody(text: item.gridPreview, isCode: false, metrics: metrics, hasTitle: showsTitleInBody)
            }
        }
    }

    private func framed(title: String?, @ViewBuilder _ content: () -> some View) -> some View {
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
            ItemFootLineView(item: item, showsTitleOnFace: showsCustomTitleOnFace)
        }
        .padding(CardMetrics.inset)
    }
}
