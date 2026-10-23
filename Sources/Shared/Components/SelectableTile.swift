// SPDX-License-Identifier: MIT
import SwiftUI

extension View {
    /// A tile in a set of choices (a theme, an icon, a swatch): one button with a name, a press action and, when it
    /// is the chosen one, the selected trait. A `Button` whose content is ignored loses its press action, which is
    /// why the Appearance pickers failed the audit, so every selectable tile states all of it here.
    func selectableTile(
        _ label: LocalizedStringKey,
        isSelected: Bool,
        perform action: @escaping () -> Void
    )
    -> some View {
        accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }

    func selectableTile(
        verbatim label: some StringProtocol,
        isSelected: Bool,
        perform action: @escaping () -> Void
    )
    -> some View {
        accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }
}
