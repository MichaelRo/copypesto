// SPDX-License-Identifier: MIT
import SwiftUI

/// A key drawn like the system keyboard's: the label fills the key with no inset of its own (the bordered style's inset
/// cut a "w" or "%" on a narrow key), a character key light and a function key (`isFunction`) grey, each with the
/// system keyboard's hairline shadow, and fainter while pressed. `isAccent` is the Done key: the brand green with the
/// ground's color on it.
struct KeyboardKeyStyle: ButtonStyle {
    var isAccent = false
    var isFunction = false

    @Environment(\.colorScheme) private var colorScheme

    private static let cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isAccent ? Color(uiColor: .systemBackground) : Color.primary)
            .background {
                // The shadow is the key's, not its letter's: on the shape alone, as the system keyboard draws it.
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 0, x: 0, y: 1)
            }
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
    }

    private func fill(pressed: Bool) -> Color {
        if isAccent { return BrandAccent.color.opacity(pressed ? 0.75 : 1) }
        let key = switch (isFunction, colorScheme == .dark) {
        case (false, false): Color.white
        case (false, true): Color.white.opacity(0.22)
        case (true, false): Color(white: 0.68)
        case (true, true): Color.white.opacity(0.12)
        }
        return pressed ? key.opacity(0.55) : key
    }
}
