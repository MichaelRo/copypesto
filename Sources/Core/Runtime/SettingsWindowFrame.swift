// SPDX-License-Identifier: MIT
import CoreGraphics

public enum SettingsWindowFrame {
    public static let minimumWidth: CGFloat = 760
    public static let minimumHeight: CGFloat = 640
    /// Taller than this the panes only add empty room: the window an older build saved (860 pt of content) came back
    /// too tall on every open.
    public static let maximumHeight: CGFloat = 780
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
}
