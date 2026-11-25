// SPDX-License-Identifier: MIT
import Foundation

/// One choice, the theme, sets the app icon too unless the person turned Match App Icon off (ADR 0013; a design
/// consult of 2026-11-25): two pickers that nearly always agree were one too many. On iOS the icon changes once,
/// when the person leaves the settings, because each change shows a system alert.
public enum AppIconMatching {
    public static func icon(for theme: AppTheme, matches: Bool, current: AppIconChoice) -> AppIconChoice {
        matches ? theme.pairedIcon : current
    }

    /// An install from before the switch existed that kept an icon other than its theme's keeps it, with matching off.
    /// Runs only while the switch has never been stored.
    public static func migrate(_ defaults: UserDefaults) {
        guard defaults.object(forKey: Setting.matchesAppIcon.name) == nil,
              defaults.object(forKey: Setting.appIcon.name) != nil else { return }
        let theme = AppTheme(stored: defaults.value(for: Setting.appTheme))
        let icon = AppIconChoice(stored: defaults.value(for: Setting.appIcon))
        defaults.set(icon == theme.pairedIcon, for: Setting.matchesAppIcon)
    }
}
