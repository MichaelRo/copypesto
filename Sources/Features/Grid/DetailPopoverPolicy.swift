// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation

enum DetailPopoverPolicy {
    static let dwell: Duration = .milliseconds(400)
    /// How long a card that scrolls waits for the pointer to cross from the clip to it, and between leaving it and
    /// closing. Long enough for a slow or unsteady hand (WCAG 1.4.13); another clip being entered closes it at once.
    static let grace: Duration = .milliseconds(450)
    private static let keyboardSafety: Duration = .seconds(30)
    private static let movementThreshold: CGFloat = 4

    /// `spent` is true once the popover has shown and timed out for this hover or reveal; it resets when the pointer
    /// leaves the card, so a popover never returns by itself.
    /// `held` is a card that scrolls while the pointer is on it or crossing to it.
    static func wantsDetail(
        hovered: Bool, keyboardRevealed: Bool, held: Bool = false, suppressed: Bool, spent: Bool
    )
    -> Bool {
        !suppressed && !spent && (hovered || keyboardRevealed || held)
    }

    static func waitsForPointer(contentScrolls: Bool) -> Bool {
        contentScrolls
    }

    static func isSuppressed(isLocked: Bool, isShelfVisible: Bool) -> Bool {
        isLocked || !isShelfVisible
    }

    static func keyboardReveals(itemID: UUID, revealedID: UUID?) -> Bool {
        itemID == revealedID
    }

    /// A hovered card lasts as long as its pointer does; a keyboard reveal that nobody closed goes after this.
    static func autoCloseDelay(hovered: Bool) -> Duration? {
        hovered ? nil : keyboardSafety
    }

    static func hoverCounts(hovered: Bool, pointerMoved: Bool) -> Bool {
        hovered && pointerMoved
    }

    /// A card lifts for the keyboard focus, or for a pointer that has really moved onto it and is not riding a scroll.
    static func isLifted(hovered: Bool, pointerMoved: Bool, scrolling: Bool, focused: Bool) -> Bool {
        (hoverCounts(hovered: hovered, pointerMoved: pointerMoved) && !scrolling) || focused
    }

    static func pointerMoved(from origin: CGPoint, to point: CGPoint) -> Bool {
        hypot(point.x - origin.x, point.y - origin.y) > movementThreshold
    }
}
