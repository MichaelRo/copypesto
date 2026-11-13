// SPDX-License-Identifier: MIT
import CoreGraphics

/// Decides when the shelf lets a dragged clip through to the app behind it. While the pointer stays inside the panel
/// the whole shelf is live, so a clip dragged up reaches a collection chip as readily as one dragged sideways. Once
/// the pointer leaves the panel the shelf is cleared (invisible, click-through) and only the chip strip comes back
/// when the pointer returns over it; returning over the cards stays cleared so a drop behind them still lands.
public enum ShelfDragClearance {
    public enum Phase: Equatable, Sendable {
        case insidePanel
        case cleared
    }

    public struct Step: Equatable, Sendable {
        public let isLive: Bool
        public let phase: Phase
    }

    /// `pointer` and `panelFrame` are in screen coordinates, with the origin at the bottom left.
    public static func step(pointer: CGPoint, panelFrame: CGRect, phase: Phase) -> Step {
        switch phase {
        case .insidePanel:
            if panelFrame.contains(pointer) { return Step(isLive: true, phase: .insidePanel) }
            return Step(isLive: false, phase: .cleared)
        case .cleared:
            return Step(
                isLive: ShelfDragZone.isOverDropZone(pointer: pointer, panelFrame: panelFrame),
                phase: .cleared
            )
        }
    }
}
