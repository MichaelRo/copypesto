// SPDX-License-Identifier: MIT
import CoreGraphics

public enum SettingsWindowFrame {
    public static let minimumWidth: CGFloat = 760
    public static let minimumHeight: CGFloat = 640
    /// Taller than this the panes only add empty room: the window an older build saved (860 pt of content) came back
    /// too tall on every open.
    public static let maximumHeight: CGFloat = 780
    public static let defaultSize = CGSize(width: 800, height: 720)
    private static let screenMargin: CGFloat = 40

    /// The saved frame, kept on a display and limited to a height that suits the Settings panes; nil when it is too
    /// small, empty or off every display, so the caller falls back to the default size.
    public static func restored(saved: CGRect, displays: [CGRect]) -> CGRect? {
        guard !saved.isEmpty, saved.width >= minimumWidth, saved.height >= minimumHeight,
              let display = displays.first(where: { $0.intersects(saved) }) else { return nil }
        let height = min(saved.height, maximumHeight, max(minimumHeight, display.height - screenMargin))
        var frame = CGRect(x: saved.minX, y: saved.maxY - height, width: saved.width, height: height)
        if frame.maxY > display.maxY { frame.origin.y = display.maxY - frame.height }
        if frame.minY < display.minY { frame.origin.y = display.minY }
        return frame
    }

    /// Where Settings opens: on `target`, the display the person is using (the shelf's, or the one under the pointer
    /// after a menu-bar click). A frame saved there comes back in place; one saved on another display keeps its size
    /// and is centered on `target`, so Settings never opens on a display the person is not looking at.
    public static func placed(
        saved: CGRect?, target: CGRect, displays: [CGRect], defaultSize: CGSize = defaultSize
    )
    -> CGRect {
        let usable = saved.flatMap { restored(saved: $0, displays: displays) }
        if let usable, target.intersects(usable) { return usable }
        let size = usable?.size ?? defaultSize
        let height = min(size.height, max(minimumHeight, target.height - screenMargin))
        let width = min(size.width, target.width)
        return CGRect(x: target.midX - width / 2, y: target.midY - height / 2, width: width, height: height)
    }
}
