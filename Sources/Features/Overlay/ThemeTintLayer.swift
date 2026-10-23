// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The theme's wash over a glass surface. It is drawn between the glass and the focused card's colour, so the glass
/// stays visible, and it is the same layer on the shelf, the floating window and the Settings preview.
struct ThemeTintLayer: View {
    let themeRaw: String
    var darkThemeRaw = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = AppTheme.resolve(light: themeRaw, dark: darkThemeRaw, isDark: scheme == .dark)
        let tint = theme.tint(dark: scheme == .dark)
        Rectangle()
            .fill(tint.flatMap { Color(hex: $0.hex) } ?? Color.clear)
            .opacity(tint?.opacity ?? 0)
            .animation(Motion.animation(.pestoWash), value: theme)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
