// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct MobileTheme: Equatable {
    let accentHex: String
    let groundHex: String

    static func resolve(accent stored: String, theme: String, darkTheme: String, isDark: Bool) -> MobileTheme {
        let resolved = AppTheme.resolve(light: theme, dark: darkTheme, isDark: isDark)
        let ground = resolved.groundHex(dark: isDark)
        let accent: String = switch AccentChoice(stored: stored) {
        case .brand: resolved.accentHex(dark: isDark)
        case let .preset(preset): ContrastRatio.readable(preset.hex(dark: isDark), on: ground, darkGround: isDark)
        case let .custom(hex): ContrastRatio.readable(hex, on: ground, darkGround: isDark)
        }
        return MobileTheme(accentHex: accent, groundHex: ground)
    }
}
