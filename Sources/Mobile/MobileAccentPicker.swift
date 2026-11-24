// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Accent color swatches for iOS Settings: the active theme's own accent ("brand"), the six named presets, and a custom
/// system color picker stored in `Setting.accentColorHex`.
struct MobileAccentPicker: View {
    @Binding var selection: String
    let theme: String
    let darkTheme: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.pestoAccent) private var accent

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var choice: AccentChoice {
        AccentChoice(stored: selection)
    }

    private var isCustom: Bool {
        if case .custom = choice { true } else { false }
    }

    private var accentName: String {
        switch choice {
        case .brand:
            let resolved = AppTheme.resolve(light: theme, dark: darkTheme, isDark: isDark)
            return String(localized: "Theme (\(resolved.displayName))")
        case let .preset(preset):
            return preset.displayName
        case .custom:
            return String(localized: "Custom")
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: {
                if case let .custom(hex) = choice, let color = Color(hex: hex) {
                    return color
                }
                let resolved = MobileTheme.resolve(
                    accent: selection, theme: theme, darkTheme: darkTheme, isDark: isDark
                )
                return Color(hex: resolved.accentHex) ?? accent
            },
            set: { newColor in
                if let hex = newColor.toHex() {
                    selection = AccentChoice.custom(hex).stored
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Accent color")
                Spacer()
                Text(accentName)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MobileAccessibilityID.accentChoice("name"))
            }
            if typeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    swatchesRow
                }
            } else {
                swatchesRow
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(MobileAccessibilityID.accentPicker)
    }

    private var swatchesRow: some View {
        HStack(spacing: 0) {
            let brandHex = AppTheme.resolve(light: theme, dark: darkTheme, isDark: isDark)
                .accentHex(dark: isDark)
            swatch(
                hex: brandHex,
                isSelected: choice == .brand,
                label: String(localized: "Theme accent"),
                id: MobileAccessibilityID.accentChoice("brand")
            ) {
                selection = AccentChoice.brand.stored
            }
            ForEach(AccentPreset.allCases, id: \.self) { preset in
                let hex = preset.hex(dark: isDark)
                swatch(
                    hex: hex,
                    isSelected: choice == .preset(preset),
                    label: preset.displayName,
                    id: MobileAccessibilityID.accentChoice(preset.rawValue)
                ) {
                    selection = AccentChoice.preset(preset).stored
                }
            }
            customPicker
        }
    }

    private func swatch(
        hex: String, isSelected: Bool, label: String, id: String, action: @escaping () -> Void
    )
    -> some View {
        let checkColor = Color(hex: ContrastRatio.labelHex(onFill: hex)) ?? .white
        return Button(action: action) {
            Circle()
                .fill(Color(hex: hex) ?? accent)
                .frame(width: 28, height: 28)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(checkColor)
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Color.primary.opacity(0.45) : .clear, lineWidth: 1.5))
                .frame(
                    minWidth: typeSize.isAccessibilitySize ? TouchTarget.minimum : 0,
                    maxWidth: typeSize.isAccessibilitySize ? TouchTarget.minimum : .infinity,
                    minHeight: TouchTarget.minimum
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private var customPicker: some View {
        ZStack {
            ColorPicker("Custom color", selection: customColorBinding, supportsOpacity: false)
                .labelsHidden()
                .accessibilityIdentifier(MobileAccessibilityID.accentChoice("custom"))
                .frame(width: 28, height: 28)
                .padding(3)
                .overlay(
                    Circle()
                        .strokeBorder(isCustom ? Color.primary.opacity(0.45) : .clear, lineWidth: 1.5)
                        .allowsHitTesting(false)
                )
        }
        .frame(
            minWidth: typeSize.isAccessibilitySize ? TouchTarget.minimum : 0,
            maxWidth: typeSize.isAccessibilitySize ? TouchTarget.minimum : .infinity,
            minHeight: TouchTarget.minimum
        )
    }
}
