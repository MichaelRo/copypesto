// SPDX-License-Identifier: MIT
import SwiftUI

/// A key drawn like the system keyboard's: the label fills the key with no inset of its own, a character key light
/// and a function key (`isFunction`) system grey, each with the system keyboard's 1 pt bottom shadow, and a pressed
/// state matching iOS. `isAccent` is the Done key: the theme's accent with its label color on it.
struct KeyboardKeyStyle: ButtonStyle {
    var isAccent = false
    var isFunction = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.pestoAccent) private var accent
    @Environment(\.pestoAccentLabel) private var accentLabel

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = sizeClass == .regular ? 8 : 6
        configuration.label
            .foregroundStyle(isAccent ? accentLabel : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.6 : 0.35),
                        radius: 0, x: 0, y: 1
                    )
            }
            .contentShape(.rect(cornerRadius: radius))
    }

    private func fill(pressed: Bool) -> Color {
        if isAccent { return accent.opacity(pressed ? 0.75 : 1) }
        switch (isFunction, colorScheme == .dark) {
        case (false, false):
            return pressed ? Color(white: 0.85) : .white
        case (false, true):
            return Color.white.opacity(pressed ? 0.45 : 0.28)
        case (true, false):
            return pressed ? .white : Color(red: 0.675, green: 0.702, blue: 0.737)
        case (true, true):
            return Color.white.opacity(pressed ? 0.30 : 0.14)
        }
    }
}
