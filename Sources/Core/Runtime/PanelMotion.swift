// SPDX-License-Identifier: MIT
import AppKit

public enum PanelMotion {
    public static func slides(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// The shelf closes faster than it opens: a paste starts when it has closed, so every millisecond of the way out is
    /// waited for (the bench measured 245 ms from the key to the start of the paste with the 0.2 s it had).
    public static let hideDuration: Double = 0.12

    /// The system Reduce Motion setting.
    @MainActor
    public static var systemReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
