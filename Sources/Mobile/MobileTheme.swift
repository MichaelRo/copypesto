// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct MobileTheme: Equatable {
    let accentHex: String
    let groundHex: String

    static func resolve(accent stored: String, theme: String, darkTheme: String, isDark: Bool) -> MobileTheme {
        let colors = WidgetSnapshot.Theme.colors(accent: stored, theme: theme, darkTheme: darkTheme, isDark: isDark)
        return MobileTheme(accentHex: colors.accent, groundHex: colors.ground)
    }
}
