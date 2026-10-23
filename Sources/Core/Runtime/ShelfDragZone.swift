// SPDX-License-Identifier: MIT
import CoreGraphics

/// While a clip is dragged out of the shelf, only the command bar (the collection chips a clip can be dropped on) keeps
/// receiving the drag. The rest of the panel lets it through, so the input box of the app behind the shelf can be
/// reached.
public enum ShelfDragZone {
    /// `pointer` and `panelFrame` are in screen coordinates, with the origin at the bottom left.
    public static func isOverDropZone(pointer: CGPoint, panelFrame: CGRect) -> Bool {
        CGRect(
            x: panelFrame.minX, y: panelFrame.maxY - ShelfHeight.commandBlock,
            width: panelFrame.width, height: ShelfHeight.commandBlock
        ).contains(pointer)
    }
}
