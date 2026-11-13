// SPDX-License-Identifier: MIT
import CoreGraphics

/// Whether the menu bar icon is somewhere a person can see it. In a crowded menu bar macOS keeps the status item but
/// places its window off the screen (or behind the notch), so Pesto's icon is "on" in Settings and nowhere to be found.
public enum MenuBarIconPlace {
    public static func isOnScreen(frame: CGRect?, screens: [CGRect]) -> Bool {
        guard let frame, !frame.isEmpty else { return false }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.contains { $0.contains(center) }
    }
}
