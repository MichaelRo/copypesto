// SPDX-License-Identifier: MIT
import CoreGraphics

public enum QuickLookPanelSizing {
    public static let widthShare: CGFloat = 0.55
    public static let heightShare: CGFloat = 0.65

    /// The preview keeps the size the system chose when that fits, and is otherwise shrunk to a share of the display so
    /// it never fills the screen the way a large document preview does; it is centred in the usable area.
    public static func frame(preferred: CGSize, in visibleFrame: CGRect) -> CGRect {
        let width = min(preferred.width, visibleFrame.width * widthShare)
        let height = min(preferred.height, visibleFrame.height * heightShare)
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
