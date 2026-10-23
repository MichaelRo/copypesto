// SPDX-License-Identifier: MIT
import CoreGraphics

/// The vertical budget of a text card: header band, the gap under it, the footer, and what is left for text.
public enum CardLayout {
    public static let headerHeight: CGFloat = 34
    public static let appTileSize: CGFloat = 20
    public static let bodyTopPadding: CGFloat = 6

    /// The footer row (a keycap or badge, about 18), its bottom padding (6), the spacer above it (4) and 8 of air, so
    /// the last line of text never touches the footer.
    public static let footerReserve: CGFloat = 36

    public static func textHeightBudget(for size: CGSize) -> CGFloat {
        max(0, size.height - headerHeight - bodyTopPadding - footerReserve)
    }

    public static func textLineLimit(for size: CGSize) -> Int {
        let line = CardTextScale.lineHeight(cardWidth: size.width)
        return max(2, Int(textHeightBudget(for: size) / line))
    }

    /// The height the lines of text may take: the line limit times the line height, so a card of paragraphs shows no
    /// more than a card of one, and a blank-line gap (`paragraphGap`) costs the third of a line it is.
    public static func textBlockHeight(for size: CGSize) -> CGFloat {
        CGFloat(textLineLimit(for: size)) * CardTextScale.lineHeight(cardWidth: size.width) + lineTolerance
    }

    /// A rendered line is a little taller than the 18 point convention (13 pt text, 2 pt spacing, scaled), so a block
    /// of
    /// exactly N lines of that height lost its last line on the small card. It is under a third of a line at any size.
    public static let lineTolerance: CGFloat = 4

    public static let paragraphGap: CGFloat = 6
}
