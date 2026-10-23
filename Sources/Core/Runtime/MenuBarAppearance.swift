// SPDX-License-Identifier: MIT

/// The menu-bar icon belongs to the menu bar, not to Pesto's windows, and not to the Mac's Light or Dark setting
/// either: the bar's own colour follows the wallpaper under it, so a Dark Mac can have a light bar (the owner saw a
/// white icon on one, ADR 0013). The status item's window is asked what the bar looks like, once with the app's
/// appearance left alone and once as the app forces it; only when forcing changes the answer is the icon pinned, and
/// then to the bar's own answer.
public enum MenuBarAppearance {
    public enum Style: Sendable, Equatable {
        case light
        case dark
    }

    /// The appearance to pin on the status item's button; nil lets it inherit.
    /// - Parameters:
    ///   - underForcedApp: what the status window reports with Light or Dark forced on the app.
    ///   - alone: what it reports with the app's appearance cleared, which is the bar's own.
    public static func pin(underForcedApp: Style, alone: Style) -> Style? {
        underForcedApp == alone ? nil : alone
    }

    public static func isSystemChrome(windowClassName: String) -> Bool {
        windowClassName.contains("StatusBarWindow")
    }
}
