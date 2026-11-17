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

    public static func frame(near cursorRect: CGRect, panelSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 8
        let panelWidth = panelSize.width
        let panelHeight = panelSize.height

        var x = cursorRect.midX - panelWidth / 2
        var y = cursorRect.maxY + gap

        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - panelWidth - 8))

        if y + panelHeight > visibleFrame.maxY {
            y = cursorRect.minY - panelHeight - gap
        }

        y = max(visibleFrame.minY + 8, min(y, visibleFrame.maxY - panelHeight - 8))

        return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }
}
