// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The four themes as cards, each half light and half dark so its real colours show whichever way Pesto is set.
/// Choosing one sets the theme and the accent together, and its icon while Match App Icon is on (`AppIconMatching`).
struct ThemePicker: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Binding var theme: String
    /// Nil for a second picker (the dark-mode theme), which sets only its own theme.
    var accentHex: Binding<String>?
    var iconRaw: Binding<String>?
    /// Match App Icon: when off, a theme leaves the icon as it is.
    var matchesIcon = true
    /// What a screen reader calls the group of tiles: "Theme", or "Theme for dark mode" on the second picker.
    var groupLabel: LocalizedStringKey = "Theme"
    @Environment(\.pestoAccent) private var accent

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AppTheme.allCases, id: \.self) { option in
                card(option)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(groupLabel)
    }

    private func card(_ option: AppTheme) -> some View {
        let isSelected = AppTheme(stored: theme) == option
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let select = {
            let applied = option.applied()
            theme = applied.theme
            accentHex?.wrappedValue = applied.accent
            if matchesIcon { iconRaw?.wrappedValue = applied.icon }
        }
        return Button(action: select) {
            VStack(spacing: 5) {
                ZStack {
                    ThemeShelfMiniature(theme: option, dark: false)
                    ThemeShelfMiniature(theme: option, dark: true).clipShape(DiagonalHalf())
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(shape)
                .overlay(alignment: .bottomTrailing) {
                    if iconRaw != nil {
                        Image(option.pairedIcon.previewImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(shape.strokeBorder(
                    isSelected ? accent : Color.primary.opacity(0.14),
                    lineWidth: isSelected ? 2.5 : 1
                ))
                Text(option.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : AdaptiveContrast.quiet(contrast))
            }
        }
        .buttonStyle(.plain)
        .animation(Motion.animation(.pestoQuick), value: isSelected)
        .help(accentHex == nil
            ? "\(option.displayName): the theme for dark mode"
            : "\(option.displayName): sets the accent, the shelf tint and Pesto\u{2019}s icon")
        .selectableTile("\(option.displayName) theme", isSelected: isSelected, perform: select)
        .accessibilityIdentifier(AccessibilityID.settingsChoice(
            accentHex == nil ? "themeDark" : "theme",
            option.rawValue
        ))
    }
}
