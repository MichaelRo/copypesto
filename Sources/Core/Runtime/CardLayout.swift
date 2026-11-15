// SPDX-License-Identifier: MIT
import CoreGraphics

/// The vertical budget of a text card: header band, the gap under it, the footer, and what is left for text.
public enum CardLayout {
    /// The source app's icon in the line of facts at the foot of the card. 18 points: the height of the keycap beside
    /// it, so the line keeps one height; 16 read as a dot next to the text and 20 outweighed the keycap (both drawn on
    /// the real shelf, 2026-11-13). Every app icon carries a 32 pt drawing, so 18 is a sharp reduction.
    public static let sourceTileSize: CGFloat = 18
    /// The content starts this far under the card's top edge, the same as its side margins. No header band sits
    /// above it (ADR 0044).
    public static let contentTopInset: CGFloat = 10

    /// Vertical space claimed by a 1-line title kicker and its gap above the body.
    public static let titleBlockReserve: CGFloat = 18

    public static func titleBlockReserve(cardWidth width: CGFloat) -> CGFloat {
        titleBlockReserve * CardTextScale.factor(forWidth: width)
    }

    /// The footer row (a keycap or badge, about 18), its bottom padding (6), the spacer above it (4) and 8 of air, so
    /// the last line of text never touches the footer.
    public static let footerReserve: CGFloat = 36

    public static let glyphTopInset: CGFloat = 16
    public static let glyphTopInsetAllowance: CGFloat = 4

    /// Extra top padding that puts a large text's capital letters `glyphTopInset` under the card's top edge whatever
    /// its size:
    /// the line box starts above the glyphs by `spaceAboveCaps` (ascender less cap height), more for a bigger size.
    public static func largeTextTopPadding(spaceAboveCaps: CGFloat) -> CGFloat {
        min(max(0, glyphTopInset - contentTopInset - spaceAboveCaps), glyphTopInsetAllowance)
    }

    public static func textHeightBudget(for size: CGSize, hasTitle: Bool = false) -> CGFloat {
        let titleReserve = hasTitle ? titleBlockReserve(cardWidth: size.width) : 0
        return max(0, size.height - contentTopInset - titleReserve - footerReserve)
    }

    public static func textLineLimit(for size: CGSize, hasTitle: Bool = false) -> Int {
        let line = CardTextScale.lineHeight(cardWidth: size.width)
        return max(2, Int(textHeightBudget(for: size, hasTitle: hasTitle) / line))
    }

    /// The height the lines of text may take: the line limit times the line height, so a card of paragraphs shows no
    /// more than a card of one, and a blank-line gap (`paragraphGap`) costs the third of a line it is.
    public static func textBlockHeight(for size: CGSize, hasTitle: Bool = false) -> CGFloat {
        CGFloat(textLineLimit(for: size, hasTitle: hasTitle))
            * CardTextScale.lineHeight(cardWidth: size.width) + lineTolerance
    }

    /// A rendered line is a little taller than the 18 point convention (13 pt text, 2 pt spacing, scaled), so a block
    /// of
    /// exactly N lines of that height lost its last line on the small card. It is under a third of a line at any size.
    public static let lineTolerance: CGFloat = 4

    public static let paragraphGap: CGFloat = 6
}
