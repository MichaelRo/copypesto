// SPDX-License-Identifier: MIT
import CoreGraphics

public enum ShelfHeight {
    public static let commandTopInset: CGFloat = 10
    /// The chip strip, or the Find bar's 28 pt field (design board 1b).
    public static let commandRowHeight: CGFloat = 28
    public static let commandBottomInset: CGFloat = 8
    /// The command bar with its padding, above the row: the same in both modes, so opening Find moves no card. Its
    /// parts are declared first: a static that reads one declared after it was folded to 0 (`ShelfHeightTests`).
    public static let commandBlock: CGFloat = commandTopInset + commandRowHeight + commandBottomInset

    /// The Find field: 480 pt on a 14-inch shelf, narrower on a smaller one so the scope and the filters keep room,
    /// never under 320.
    public static func searchFieldWidth(shelfWidth: CGFloat) -> CGFloat {
        min(480, max(320, (shelfWidth * 0.32).rounded()))
    }

    /// The row's scroll area is the cards plus this, half above and half below, so a lifted or selected card has room.
    public static let liftRoom: CGFloat = 40
    /// What is left under the scroll area. The selection bar floats in it, over half of the lift room.
    public static let bottomSlot: CGFloat = 26

    public static let chrome: CGFloat = commandBlock + liftRoom + bottomSlot

    public static func height(forCardHeight cardHeight: CGFloat) -> CGFloat {
        cardHeight + chrome
    }

    public static func topOverflow(measuredHeight: CGFloat, isSearchActive: Bool = false) -> CGFloat {
        _ = isSearchActive
        return max(0, measuredHeight - commandBlock)
    }

    /// Equal breathing room above and below a 30 pt bottom capsule (`SelectionActionBar`, Undo, suggestions, hint).
    public static func bottomCapsuleInset(isSearchActive: Bool = false) -> CGFloat {
        _ = isSearchActive
        return 8
    }
}
