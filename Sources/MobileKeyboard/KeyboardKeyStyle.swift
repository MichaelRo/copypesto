// SPDX-License-Identifier: MIT
import SwiftUI

/// A key drawn like the system keyboard's: the label fills the key with no inset of its own (the bordered style's inset
/// cut a "w" or "%" on a narrow key), on the key color of light or dark, darker while pressed. `isAccent` is the
/// Done key: the brand green with the ground's color on it.
struct KeyboardKeyStyle: ButtonStyle {
    var isAccent = false

    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isAccent ? Color(uiColor: .systemBackground) : Color.primary)
            .background(fill(pressed: configuration.isPressed), in: .rect(cornerRadius: 6))
            .contentShape(.rect(cornerRadius: 6))
    }

    private func fill(pressed: Bool) -> Color {
        if isAccent { return BrandAccent.color.opacity(pressed ? 0.75 : 1) }
        let key = colorScheme == .dark ? Color.white.opacity(0.22) : Color.white
        return pressed ? key.opacity(0.55) : key
    }
}
