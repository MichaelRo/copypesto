// SPDX-License-Identifier: MIT
import CoreGraphics

public enum ScreenCoordinates {
    /// AX rects have their origin at the top-left of the primary screen; Cocoa's is the bottom-left of it.
    /// The flip must use the primary screen's height, not `NSScreen.main` (the screen with the key window).
    public static func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
