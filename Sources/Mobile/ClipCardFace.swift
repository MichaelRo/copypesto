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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let metrics = CardMetrics(width: width, typeSize: typeSize)
        switch face {
        case let .covered(isSecret):
            CoveredCardFace(item: item, isSecret: isSecret)
        case .shownSecret:
            framed { SecretShownBody(item: item, text: media.revealedText, metrics: metrics) }
        case let .picture(fills, isAnimated):
            PictureCardFace(
                image: media.picture?.image, fillsCard: fills,
                animation: playsAnimation ? media.picture?.animation : nil
            ) {
                CardFootLineView(item: item, onPicture: true, showsGIF: isAnimated)
            }
        case .linkPicture:
            PictureCardFace(image: media.linkPicture, fillsCard: true) {
                CardFootLineView(item: item, onPicture: true)
            }
        case let .color(fill, ink):
            ColorCardFace(item: item, fill: fill, ink: ink, metrics: metrics)
        case let .largeText(points):
            framed { LargeTextBody(text: CardPreviewText.display(item.gridPreview), points: points, metrics: metrics) }
        case let .link(link):
            framed { LinkBody(link: link, metrics: metrics) }
        case .code:
            framed { PlainTextBody(text: item.gridPreview, isCode: true, metrics: metrics) }
        case .file:
            framed { FileBody(preview: item.gridPreview) }
        case .text:
            framed { PlainTextBody(text: item.gridPreview, isCode: false, metrics: metrics) }
        }
    }

    private func framed(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CardMetrics.footGap) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            CardFootLineView(item: item)
        }
        .padding(CardMetrics.inset)
    }
}
