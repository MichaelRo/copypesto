// SPDX-License-Identifier: MIT
import CoreGraphics

/// Where a status toast's bottom-left corner goes. Pure geometry, in screen coordinates (origin at the bottom left).
public enum ToastPlacement {
    static let belowIconGap: CGFloat = 8
    static let belowBarGap: CGFloat = 16
    static let edgeMargin: CGFloat = 12
    static let aboveDock: CGFloat = 80

    /// `anchor` is the menu bar icon's frame. It is used only when it is a real frame on this screen: an icon on
    /// another display, or one the system has hidden (no room, or turned off in Settings), centres the toast instead.
    public static func origin(
        for placement: StatusToast.Placement, size: CGSize, visibleFrame: CGRect, screenFrame: CGRect, anchor: CGRect?
    )
    -> CGPoint {
        let centred = visibleFrame.midX - size.width / 2
        switch placement {
        case .aboveDock:
            return CGPoint(x: centred, y: visibleFrame.minY + aboveDock)
        case .belowMenuBar:
            guard let icon = anchor, !icon.isEmpty, screenFrame.intersects(icon) else {
                return CGPoint(x: centred, y: visibleFrame.maxY - size.height - belowBarGap)
            }
            let lowest = visibleFrame.minX + edgeMargin
            let highest = visibleFrame.maxX - size.width - edgeMargin
            let x = min(max(icon.midX - size.width / 2, lowest), max(lowest, highest))
            return CGPoint(x: x, y: icon.minY - belowIconGap - size.height)
        }
    }
}
