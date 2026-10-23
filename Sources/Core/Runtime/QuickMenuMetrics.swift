// SPDX-License-Identifier: MIT
import CoreGraphics

public enum QuickMenuMetrics {
    public static let spacing: CGFloat = 8
    public static let horizontalPadding: CGFloat = 12
    public static let verticalPadding: CGFloat = 10

    public static func panelSize(cardSize: CGSize, cards: Int, maxWidth: CGFloat) -> CGSize {
        let slots = CGFloat(max(cards, 1))
        let natural = slots * cardSize.width + (slots - 1) * spacing + 2 * horizontalPadding
        return CGSize(width: min(natural, maxWidth), height: cardSize.height + 2 * verticalPadding)
    }
}
