// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The chosen theme's accent for every view below the root, as the Mac's window roots give theirs.
struct MobileAccent: ViewModifier {
    @AppStorage(Setting.appTheme) private var theme: String
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let accent = Color(hex: AppTheme(stored: theme).accentHex(dark: colorScheme == .dark)) ?? .green
        return content
            .tint(accent)
            .environment(\.pestoAccent, accent)
    }
}
