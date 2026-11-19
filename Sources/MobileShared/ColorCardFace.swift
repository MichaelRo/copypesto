// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The whole card is the color; its text and its line of facts are in black or white, whichever reads on the fill.
struct ColorCardFace<Foot: View>: View {
    let text: String
    let fill: HexColorComponents
    let ink: CardInk
    let metrics: CardMetrics
    var title: String?
    @ViewBuilder let foot: () -> Foot

    var body: some View {
        let inkColor: Color = ink == .white ? .white : .black
        let label = CardPreviewText.display(text)
        ZStack(alignment: .bottomLeading) {
            Color(.sRGB, red: fill.red, green: fill.green, blue: fill.blue, opacity: fill.alpha)
            VStack(alignment: .leading, spacing: CardMetrics.footGap) {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(inkColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(label)
                        .scaledFont(
                            size: metrics.points(CardInk.labelPoints(forLength: label.count)),
                            weight: .semibold,
                            maxScale: CardMetrics.maxTextScale
                        )
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(inkColor)
                }
                foot()
            }
            .padding(CardMetrics.inset)
        }
        .environment(\.colorScheme, ink == .white ? .dark : .light)
    }
}
