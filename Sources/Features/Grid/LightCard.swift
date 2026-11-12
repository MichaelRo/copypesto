// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What a card shows for a moment while the shelf is switching collections faster than it can draw them: the card's own
/// frame, border and fill, the header band in its source app's colour and a few quiet lines where the text will be. It
/// reads one or two values of the clip and has no tasks, gestures or accessibility of its own; the real card replaces
/// it
/// when the shelf has been still for `SwitchQualityPolicy.settle`.
struct LightCard: View {
    let item: ClipboardItem
    var isFocused = false
    @AppStorage(Setting.cardSize) private var cardSizeRaw: String
    @AppStorage(Setting.cardWidth) private var cardWidth: Int
    @Environment(\.pestoAccent) private var accent

    private static let cornerRadius: CGFloat = 12
    private static let lineWidths: [CGFloat] = [1, 0.9, 0.96, 0.55]

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color.primary.opacity(0.09))
            .frame(width: width, height: height)
    }

    var body: some View {
        let size = CardSize.dimensions(sizeRaw: cardSizeRaw, customWidth: cardWidth)
        let tint = item.sourceDominantColorHex.flatMap { Color(hex: $0) } ?? Color.primary
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(tint.opacity(0.14))
                .frame(height: CardLayout.headerHeight)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Self.lineWidths.indices, id: \.self) { index in
                    bar(width: (size.width - 20) * Self.lineWidths[index], height: 8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 16)
            Spacer(minLength: 0)
            HStack {
                bar(width: 30, height: 16)
                Spacer(minLength: 0)
                bar(width: 62, height: 16)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .modifier(GlassCardModifier(
            isSelected: false, isFocused: isFocused, isHovered: false, isLifted: false,
            cornerRadius: Self.cornerRadius
        ))
        .accessibilityHidden(true)
    }
}
