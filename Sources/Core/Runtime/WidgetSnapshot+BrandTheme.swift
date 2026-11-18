// SPDX-License-Identifier: MIT
import Foundation

public extension WidgetSnapshot.Theme {
    /// Basil's, for a widget with no snapshot to read.
    static let brand = WidgetSnapshot.Theme(
        lightGround: AppTheme.basil.groundHex(dark: false), darkGround: AppTheme.basil.groundHex(dark: true),
        lightAccent: AppTheme.basil.accentHex(dark: false), darkAccent: AppTheme.basil.accentHex(dark: true)
    )

    /// The ground and accent the app draws in one appearance, from the stored accent and the light and dark theme: the
    /// theme's own accent, or a chosen one moved just far enough to read as text on that ground.
    static func colors(accent stored: String, theme: String, darkTheme: String, isDark: Bool)
    -> (accent: String, ground: String) {
        let resolved = AppTheme.resolve(light: theme, dark: darkTheme, isDark: isDark)
        let ground = resolved.groundHex(dark: isDark)
        let accent: String = switch AccentChoice(stored: stored) {
        case .brand: resolved.accentHex(dark: isDark)
        case let .preset(preset): ContrastRatio.readable(preset.hex(dark: isDark), on: ground, darkGround: isDark)
        case let .custom(hex): ContrastRatio.readable(hex, on: ground, darkGround: isDark)
        }
        return (accent, ground)
    }

    /// Both appearances, for a widget that cannot read the app's settings.
    static func resolve(accent: String, theme: String, darkTheme: String) -> WidgetSnapshot.Theme {
        let light = colors(accent: accent, theme: theme, darkTheme: darkTheme, isDark: false)
        let dark = colors(accent: accent, theme: theme, darkTheme: darkTheme, isDark: true)
        return WidgetSnapshot.Theme(
            lightGround: light.ground, darkGround: dark.ground, lightAccent: light.accent, darkAccent: dark.accent
        )
    }
}
