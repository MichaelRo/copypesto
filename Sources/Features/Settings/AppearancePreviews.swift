// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A miniature shelf in the chosen appearance and the current theme; "System" is split down the middle.
struct AppearanceModePreview: View {
    let mode: AppearanceMode
    let themeRaw: String
    var darkThemeRaw = ""

    var body: some View {
        let light = AppTheme.resolve(light: themeRaw, dark: darkThemeRaw, isDark: false)
        let dark = AppTheme.resolve(light: themeRaw, dark: darkThemeRaw, isDark: true)
        ZStack {
            switch mode {
            case .light: ThemeShelfMiniature(theme: light, dark: false)
            case .dark: ThemeShelfMiniature(theme: dark, dark: true)
            case .system:
                ThemeShelfMiniature(theme: light, dark: false)
                ThemeShelfMiniature(theme: dark, dark: true).clipShape(RightHalf())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(5)
    }
}

/// The accent colour choices, in the order of macOS's own Appearance settings: the theme's colour first (what
/// "Multicolor" means for an app that has its own), the named colours, then any colour from the system colour panel.
struct AccentSwatches: View {
    @Environment(\.pestoAccent) private var accent
    @AppStorage(Setting.appTheme) private var appThemeRaw: String
    @Binding var hex: String
    let identifier: (String) -> String
    @State private var showCustomPicker = false

    private var choice: AccentChoice {
        AccentChoice(stored: hex)
    }

    private var customIsSelected: Bool {
        if case .custom = choice { true } else { false }
    }

    var body: some View {
        HStack(spacing: 12) {
            swatch(
                fill: AnyShapeStyle(Color.pestoAccent(stored: AccentChoice.defaultStored, theme: appThemeRaw)),
                isSelected: choice == .brand, label: "Accent color: Theme", id: identifier("brand")
            ) {
                showCustomPicker = false
                hex = AccentChoice.brand.stored
                AccentColorPanel.shared.close()
            }
            ForEach(AccentPreset.allCases, id: \.self) { preset in
                swatch(
                    fill: AnyShapeStyle(Color.presetAccent(preset)),
                    isSelected: choice == .preset(preset),
                    label: "Accent color: \(preset.displayName)", id: identifier(preset.rawValue)
                ) {
                    showCustomPicker = false
                    hex = AccentChoice.preset(preset).stored
                    AccentColorPanel.shared.close()
                }
            }
            swatch(
                fill: customIsSelected ? AnyShapeStyle(Color.pestoAccent(stored: hex, theme: appThemeRaw)) :
                    AnyShapeStyle(.clear),
                isSelected: customIsSelected, label: "Accent color: Other", id: identifier("custom"),
                showsOutline: !customIsSelected
            ) {
                showCustomPicker.toggle()
                AccentColorPanel.shared.show(current: Color.pestoAccent(stored: hex, theme: appThemeRaw)) { hex = $0 }
            }
            .popover(isPresented: $showCustomPicker, arrowEdge: .bottom) {
                InlineColorPickerPopover(
                    hex: $hex,
                    fallbackColor: Color.pestoAccent(stored: hex, theme: appThemeRaw)
                )
            }
        }
    }

    private func swatch(
        fill: AnyShapeStyle, isSelected: Bool, label: String, id: String, showsOutline: Bool = false,
        action: @escaping () -> Void
    )
    -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fill).frame(width: 24, height: 24)
                if showsOutline {
                    Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 24, height: 24)
                    Image(systemName: "plus").font(.caption2.weight(.heavy)).pestoQuiet()
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                    Circle().strokeBorder(.white, lineWidth: 2).frame(width: 24, height: 24)
                    Circle().strokeBorder(accent.opacity(0.9), lineWidth: 2).frame(width: 32, height: 32)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .selectableTile(verbatim: label, isSelected: isSelected, perform: action)
        .accessibilityIdentifier(id)
    }
}

/// A live picture of the shelf at the top of Appearance: card size, light or dark, accent and theme, drawn the way the
/// shelf draws them. Nothing here reads the user's real clips.
struct SettingsShelfPreview: View {
    let cardDimensions: CGSize
    let appearance: AppearanceMode
    let accentHex: String
    let themeRaw: String
    var darkThemeRaw = ""
    var position: ShelfPosition = .bottom

    private static let scale: CGFloat = 0.62

    @Environment(\.colorScheme) private var colorSchemeFallback

    private var accent: Color {
        Color.pestoAccent(stored: accentHex, theme: themeRaw, darkTheme: darkThemeRaw)
    }

    private var scheme: ColorScheme {
        switch appearance {
        case .system: colorSchemeFallback
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        let dimensions = cardDimensions
        let barHeight = dimensions.height * Self.scale + 24
        let atTop = position == .underNotch
        let barShape = atTop
            ? UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
        ZStack(alignment: atTop ? .top : .bottom) {
            BrandBackdropView()
            HStack(spacing: 8) {
                SampleCardStrip(
                    kinds: [.text, .link, .color], scale: Self.scale, focusesFirst: true,
                    cardIdentifier: AccessibilityID.settingsPreviewCard
                )
                .environment(\.pestoAccent, accent)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                barShape.fill(.regularMaterial)
                    .overlay { ThemeTintLayer(themeRaw: themeRaw, darkThemeRaw: darkThemeRaw).clipShape(barShape) }
            )
            .overlay(barShape.strokeBorder(Color.primary.opacity(0.10)))
            .padding(.horizontal, 24)
            .padding(atTop ? .bottom : .top, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: barHeight + 32)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
        .environment(\.colorScheme, scheme)
        .animation(Motion.animation(.easeOut(duration: 0.2)), value: cardDimensions.width)
        // The tint, the dots and the borders change together, so a theme reads as one change and not as a tint that
        // lags behind colours that jumped.
        .animation(Motion.animation(.pestoWash), value: themeRaw)
        .animation(Motion.animation(.pestoWash), value: darkThemeRaw)
        .animation(Motion.animation(.pestoWash), value: accentHex)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of the shelf")
        .accessibilityIdentifier(AccessibilityID.settingsPreviewShelf)
    }
}

/// Shows what each content-filter choice does to a flagged clip.
struct FilterModePreview: View {
    @Environment(\.pestoAccent) private var accent
    let mode: NSFWMode

    var body: some View {
        HStack(spacing: 6) {
            miniCard(flagged: false)
            switch mode {
            case .blur:
                miniCard(flagged: true).overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.ultraThinMaterial)
                    Image(systemName: "eye.slash.fill").pestoCaption()
                }
            case .hide:
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .frame(width: 30, height: 46)
            case .show:
                miniCard(flagged: true)
            }
        }
    }

    private func miniCard(flagged: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(.background)
            .overlay(alignment: .topLeading) {
                Circle().fill(flagged ? Color.orange.opacity(0.8) : accent.opacity(0.8))
                    .frame(width: 6, height: 6).padding(5)
            }
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.14)))
            .frame(width: 30, height: 46)
    }
}
