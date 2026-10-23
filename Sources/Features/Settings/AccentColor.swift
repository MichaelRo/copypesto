// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

extension Color {
    /// The app's accent for a stored `accentColorHex` value. The brand green switches shade with the appearance so it
    /// stays readable as text in both light and dark.
    static func pestoAccent(
        stored: String, theme: String = Setting.appTheme.defaultValue, darkTheme: String = ""
    )
    -> Color {
        let themed = themedAccent(light: theme, dark: darkTheme)
        switch AccentChoice(stored: stored) {
        case let .preset(preset): return readableAccent(light: theme, dark: darkTheme) { preset.hex(dark: $0) }
        case .brand: return themed
        case let .custom(hex): return Color(hex: hex) == nil ? themed :
            readableAccent(light: theme, dark: darkTheme) { _ in hex }
        }
    }

    /// A chosen accent, moved just far enough to read as text on the current theme's ground (a preset on another
    /// theme's wash, or any color the person picked).
    private static func readableAccent(
        light: String,
        dark darkTheme: String,
        hex: @escaping (Bool) -> String
    )
    -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let resolved = AppTheme.resolve(light: light, dark: darkTheme, isDark: dark)
            let adjusted = ContrastRatio.readable(hex(dark), on: resolved.groundHex(dark: dark), darkGround: dark)
            return NSColor(hex: adjusted) ?? .controlAccentColor
        })
    }

    /// The label for a button filled with `pestoAccent`: dark where white would not read (the dark-mode green).
    static func pestoAccentLabel(
        stored: String, theme: String = Setting.appTheme.defaultValue, darkTheme: String = ""
    )
    -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let resolved = AppTheme.resolve(light: theme, dark: darkTheme, isDark: dark)
            let ground = resolved.groundHex(dark: dark)
            let fill: String = switch AccentChoice(stored: stored) {
            case let .preset(preset): ContrastRatio.readable(preset.hex(dark: dark), on: ground, darkGround: dark)
            case .brand: resolved.accentHex(dark: dark)
            case let .custom(hex): ContrastRatio.readable(hex, on: ground, darkGround: dark)
            }
            return NSColor(hex: ContrastRatio.labelHex(onFill: fill)) ?? .white
        })
    }

    static func presetAccent(_ preset: AccentPreset) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: preset.hex(dark: dark)) ?? .controlAccentColor
        })
    }

    /// The theme's accent, which switches shade with the appearance so it stays readable as text in light and dark.
    static func themedAccent(light: String, dark darkTheme: String = "") -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let theme = AppTheme.resolve(light: light, dark: darkTheme, isDark: dark)
            return NSColor(hex: theme.accentHex(dark: dark)) ?? .controlAccentColor
        })
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        guard let parsed = HexColorParser.parse(hex) else { return nil }
        self.init(
            srgbRed: CGFloat(parsed.red),
            green: CGFloat(parsed.green),
            blue: CGFloat(parsed.blue),
            alpha: CGFloat(parsed.alpha)
        )
    }
}
