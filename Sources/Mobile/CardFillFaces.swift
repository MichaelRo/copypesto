// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// A picture fills its card edge to edge when its shape is near the card's; otherwise it is shown whole over a blurred,
/// darkened still copy of itself (ADR 0041). The line of facts sits on pills, never on a scrim.
struct PictureCardFace<Foot: View>: View {
    let image: UIImage?
    let fillsCard: Bool
    var animation: GIFFrames.Animation?
    @ViewBuilder let foot: () -> Foot

    var body: some View {
        ZStack(alignment: .bottom) {
            picture
            foot()
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            if fillsCard {
                filled(image)
            } else {
                ZStack {
                    filled(image)
                        .blur(radius: 14, opaque: true)
                        .overlay(Color.black.opacity(0.35))
                    still(image, fills: false)
                        .padding(.bottom, 30)
                }
            }
        } else {
            Color.secondary.opacity(0.10)
        }
    }

    private func filled(_ image: UIImage) -> some View {
        Color.clear
            .overlay { still(image, fills: true) }
            .clipped()
    }

    @ViewBuilder
    private func still(_ image: UIImage, fills: Bool) -> some View {
        if let animation {
            AnimatedPicture(animation: animation, fills: fills)
        } else if fills {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image(uiImage: image).resizable().scaledToFit()
        }
    }
}

/// The whole card is the color; its text and its line of facts are in black or white, whichever reads on the fill.
struct ColorCardFace: View {
    let item: ClipboardItem
    let fill: HexColorComponents
    let ink: CardInk
    let metrics: CardMetrics

    var body: some View {
        let inkColor: Color = ink == .white ? .white : .black
        let label = CardPreviewText.display(item.gridPreview)
        ZStack(alignment: .bottomLeading) {
            Color(.sRGB, red: fill.red, green: fill.green, blue: fill.blue, opacity: fill.alpha)
            VStack(alignment: .leading, spacing: CardMetrics.footGap) {
                Text(label)
                    .scaledFont(
                        size: metrics.points(CardInk.labelPoints(forLength: label.count)),
                        weight: .semibold,
                        maxScale: CardMetrics.maxTextScale
                    )
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(inkColor)
                CardFootLineView(item: item, ink: inkColor)
            }
            .padding(CardMetrics.inset)
        }
        .environment(\.colorScheme, ink == .white ? .dark : .light)
    }
}
