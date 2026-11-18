// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The theme's ground and accent from the snapshot, and a color clip's swatch with its ink, as the card draws them.
struct WidgetPalette {
    let ground: Color
    let accent: Color
    let isDark: Bool

    init(theme: WidgetSnapshot.Theme, isDark: Bool) {
        self.isDark = isDark
        ground = Self.color(theme.ground(dark: isDark)) ?? .clear
        accent = Self.color(theme.accent(dark: isDark)) ?? .green
    }

    /// The hairline-bordered card inside a row: white on a light ground, white at 10 percent on a dark one.
    var card: Color {
        isDark ? .white.opacity(0.1) : .white
    }

    var hairline: Color {
        .primary.opacity(isDark ? 0.18 : 0.12)
    }

    static func color(_ hex: String) -> Color? {
        HexColorParser.parse(hex).map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: 1) }
    }

    func ink(onSwatch hex: String) -> Color {
        guard let fill = HexColorParser.parse(hex) else { return .primary }
        return CardInk.forFill(fill, backdropIsDark: isDark) == .white ? .white : .black
    }
}
