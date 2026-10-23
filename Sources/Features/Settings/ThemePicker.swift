// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The four themes as cards, each half light and half dark so its real colours show whichever way Pesto is set.
/// Choosing one sets the theme, its icon and the accent together; the accent and the icon can be changed on their own
/// afterwards.
struct ThemePicker: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Binding var theme: String
    /// Nil for a second picker (the dark-mode theme), which sets only its own theme.
    var accentHex: Binding<String>?
    var iconRaw: Binding<String>?
    /// What a screen reader calls the group of tiles: "Theme", or "Theme for dark mode" on the second picker.
    var groupLabel: LocalizedStringKey = "Theme"
    @Environment(\.pestoAccent) private var accent

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
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
            iconRaw?.wrappedValue = applied.icon
        }
        return Button(action: select) {
            VStack(spacing: 6) {
                ZStack {
                    ThemeShelfMiniature(theme: option, dark: false)
                    ThemeShelfMiniature(theme: option, dark: true).clipShape(DiagonalHalf())
                }
                .aspectRatio(3 / 2, contentMode: .fit)
                .clipShape(shape)
                .overlay(alignment: .bottomTrailing) {
                    if iconRaw != nil {
                        Image(option.pairedIcon.previewImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(shape.strokeBorder(
                    isSelected ? accent : Color.primary.opacity(0.14),
                    lineWidth: isSelected ? 2.5 : 1
                ))
                Text(option.displayName)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : AdaptiveContrast.quiet(contrast))
            }
        }
        .buttonStyle(.plain)
        .animation(Motion.animation(.easeOut(duration: 0.15)), value: isSelected)
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
