// SPDX-License-Identifier: MIT
import Foundation

/// How much the locked shelf hides of what is behind the lock screen. A blur of 10 left a picture's shape and a
/// chip's name ("Notes") readable to anyone walking past (D-01); at 30 points a 13 pt letter is smeared past
/// recognition, and the flat layer takes what contrast is left.
public enum ShelfLockCover {
    public static let blurRadius = 30.0
    public static let flatteningOpacity = 0.5

    /// The smallest text on the shelf is 10 pt, and a blur whose radius is not at least twice that is no cover.
    public static let smallestTextPoints = 10.0
    public static let hidesSmallestText = blurRadius >= 2 * smallestTextPoints
}

/// The fill behind a destructive confirmation's label: white text on it must read at 4.5:1 in light and dark (A-09).
public enum DestructiveFill {
    public static let lightHex = "BD121C"
    public static let darkHex = "C72A2A"
}
