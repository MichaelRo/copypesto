// SPDX-License-Identifier: MIT
import SwiftUI

extension View {
    /// Gives a window's content the user's accent: the tint, the drawn accent and the label for a filled button.
    func pestoAccented(stored: String, theme: String, darkTheme: String) -> some View {
        let accent = Color.pestoAccent(stored: stored, theme: theme, darkTheme: darkTheme)
        let label = Color.pestoAccentLabel(stored: stored, theme: theme, darkTheme: darkTheme)
        return tint(accent)
            .environment(\.pestoAccent, accent)
            .environment(\.pestoAccentLabel, label)
    }
}
