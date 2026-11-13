// SPDX-License-Identifier: MIT

/// The drag-end monitor clears the drag flags; this check is the safety net for a drag that ended without a mouse-up
/// the monitor saw, and it must not fire while the button is still held (it would let the shelf close mid-drag).
public enum DragStateFallback {
    public enum Decision: Equatable, Sendable {
        case checkAgain
        case clear
        case stop
    }

    public static func decide(stillThisDrag: Bool, buttonDown: Bool) -> Decision {
        guard stillThisDrag else { return .stop }
        return buttonDown ? .checkAgain : .clear
    }
}
