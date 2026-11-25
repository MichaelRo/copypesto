// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

// MARK: - Glass card background modifier

/// On macOS 26+: standard cards get `.glassEffect()` (glass provides both fill and border).
/// Image cards keep a thin manual border — glass on a full-bleed thumbnail degrades readability.
/// On macOS 15: falls back to the classic `.ultraThinMaterial` + stroke approach.
/// Cards are content, not chrome: a plain material with an adaptive border. Liquid Glass is reserved for the shelf.
struct GlassCardModifier: ViewModifier {
    @Environment(\.pestoAccent) var accent
    let isSelected: Bool
    let isFocused: Bool
    let isHovered: Bool
    let isLifted: Bool
    var isSuggested: Bool = false
    let cornerRadius: CGFloat
    /// The source app's color at the card's foot (ADR 0068); `showsGlow` is false on a picture, a color or a covered
    /// card.
    var glowColorHex: String?
    var showsGlow = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shelfDrawsGlass) private var shelfDrawsGlass
    @AppStorage(Setting.appTheme) private var themeRaw: String
    @AppStorage(Setting.appThemeDark) private var darkThemeRaw: String

    private var glow: CardGlow? {
        guard showsGlow else { return nil }
        let isDark = colorScheme == .dark
        let theme = AppTheme.resolve(light: themeRaw, dark: darkThemeRaw, isDark: isDark)
        return CardGlow.decide(
            colorHex: glowColorHex, themeAccentHex: theme.accentHex(dark: isDark), isDark: isDark,
            isGlass: shelfDrawsGlass ?? false, increaseContrast: contrast == .increased, isSelected: isSelected
        )
    }

    @Environment(\.colorSchemeContrast) private var contrast

    private var borderColor: Color {
        if isSelected || isFocused || isSuggested { return accent }
        let base = contrast == .increased ? 0.45 : 0.14
        return Color.primary.opacity(isHovered ? base * 1.6 : base)
    }

    private var lineWidth: CGFloat {
        if isSuggested { return 2.0 }
        if isSelected || isFocused { return 1.5 }
        return 0.75
    }

    func body(content: Content) -> some View {
        content
            .background {
                // The shadow belongs to this fill alone: cast by the whole card it re-blurred the text and pictures
                // on top of it each frame.
                RoundedRectangle(cornerRadius: cornerRadius).adaptiveCardFill()
                    .overlay { CardGlowView(glow: glow).clipShape(RoundedRectangle(cornerRadius: cornerRadius)) }
                    .shadow(
                        color: .black.opacity(isLifted ? 0.28 : 0.10),
                        radius: isLifted ? 14 : 4,
                        y: isLifted ? 8 : 2
                    )
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(accent.opacity(0.14))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: lineWidth)
            }
    }
}
