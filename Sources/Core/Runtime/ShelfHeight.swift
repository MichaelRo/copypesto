// SPDX-License-Identifier: MIT
import CoreGraphics

public enum ShelfHeight {
    /// The command bar with its padding, above the row.
    public static let commandBlock: CGFloat = 46
    /// The row's scroll area is the cards plus this, half above and half below, so a lifted or selected card has room.
    public static let liftRoom: CGFloat = 40
    /// What is left under the scroll area. The selection bar floats in it, over half of the lift room.
    public static let bottomSlot: CGFloat = 26

    public static let chrome: CGFloat = commandBlock + liftRoom + bottomSlot

    public static func height(forCardHeight cardHeight: CGFloat) -> CGFloat {
        cardHeight + chrome
    }
}
