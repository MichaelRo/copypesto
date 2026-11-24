// SPDX-License-Identifier: MIT
import CoreGraphics

public enum ShelfHeight {
    /// The command bar with its padding, above the row.
    public static let commandBlock: CGFloat = 46
    /// The command bar while Find & filters are open, keeping the whole shelf height unchanged.
    public static let searchCommandBlock: CGFloat = 64
    /// The row's scroll area is the cards plus this, half above and half below, so a lifted or selected card has room.
    public static let liftRoom: CGFloat = 40
    /// Card lift room while search & filters are open.
    public static let searchLiftRoom: CGFloat = 24
    /// What is left under the scroll area. The selection bar floats in it, over half of the lift room.
    public static let bottomSlot: CGFloat = 26
    /// Bottom slot while search & filters are open (`searchCommandBlock + searchLiftRoom + searchBottomSlot ==
    /// chrome`).
    public static let searchBottomSlot: CGFloat = 24

    public static let chrome: CGFloat = commandBlock + liftRoom + bottomSlot

    public static func height(forCardHeight cardHeight: CGFloat) -> CGFloat {
        cardHeight + chrome
    }

    public static func topOverflow(measuredHeight: CGFloat, isSearchActive: Bool) -> CGFloat {
        let budget = isSearchActive ? searchCommandBlock : commandBlock
        return max(0, measuredHeight - budget)
    }

    /// Equal breathing room above and below a 30 pt bottom capsule (`SelectionActionBar`, Undo, suggestions, hint).
    public static func bottomCapsuleInset(isSearchActive: Bool) -> CGFloat {
        isSearchActive ? (searchLiftRoom / 2 + searchBottomSlot - 30) / 2 : 8
    }
}
