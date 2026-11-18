// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The theme's accent and ground for every view below the root, as the Mac's window roots give theirs, and the one
/// place the person's Light or Dark choice is applied (iOS has no `NSApp.appearance`; `preferredColorScheme` here
/// reaches the window and every sheet it presents).
struct MobileAccent: ViewModifier {
    @AppStorage(Setting.appTheme) private var theme: String
    @AppStorage(Setting.appThemeDark) private var darkTheme: String
    @AppStorage(Setting.accentColorHex) private var accent: String
    @AppStorage(Setting.appearanceMode) private var appearance: String
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let resolved = MobileTheme.resolve(
            accent: accent, theme: theme, darkTheme: darkTheme, isDark: colorScheme == .dark
        )
        let accentColor = Color(hex: resolved.accentHex) ?? .green
        return content
            .tint(accentColor)
            .environment(\.pestoAccent, accentColor)
            .environment(\.pestoAccentLabel, Color(hex: ContrastRatio.labelHex(onFill: resolved.accentHex)) ?? .white)
            .environment(\.pestoSurface, Color(hex: resolved.groundHex) ?? .opaqueSurface)
            .preferredColorScheme(MobileTheme.colorScheme(appearance: appearance))
    }
}
