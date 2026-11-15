// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The theme's accent and ground for every view below the root, as the Mac's window roots give theirs. The person's
/// Light or Dark choice is applied to the windows by `MobileAppearanceBridge`, and read back here as the color scheme.
struct MobileAccent: ViewModifier {
    @AppStorage(Setting.appTheme) private var theme: String
    @AppStorage(Setting.appThemeDark) private var darkTheme: String
    @AppStorage(Setting.accentColorHex) private var accent: String
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
            .modifier(MobileAppearanceBridge())
    }
}
