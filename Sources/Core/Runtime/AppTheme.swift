// SPDX-License-Identifier: MIT
import Foundation

/// The look the person picked in Settings → Appearance: an accent pair, a wash of colour over the shelf's glass and the
/// app icon that goes with it. Basil is Pesto exactly as it was before themes. Picking a theme sets all three, and the
/// accent and the icon can still be changed on their own afterwards (ADR 0013). The order is three ingredients and then
/// the bowl they are pounded in: Basil, Parmesan, Pine nut, Mortar (ADR 0013).
public enum AppTheme: String, CaseIterable, Sendable {
    case basil
    case parmesan
    case pineNut
    case mortar

    public struct Tint: Equatable, Sendable {
        public let hex: String
        public let opacity: Double
    }

    public struct Applied: Equatable, Sendable {
        public let theme: String
        public let icon: String
        public let accent: String
    }

    public init(stored: String) {
        self = Self(rawValue: stored) ?? .basil
    }

    /// The theme that applies in the current appearance. Dark uses its own pick only when there is one (the stored
    /// value is empty when the person has not asked for a different theme in dark), and the app icon, which cannot
    /// change with the appearance, follows the light pick.
    public static func resolve(light: String, dark: String, isDark: Bool) -> AppTheme {
        isDark && AppTheme(rawValue: dark) != nil ? AppTheme(stored: dark) : AppTheme(stored: light)
    }

    public var displayName: String {
        switch self {
        case .basil: "Basil"
        case .parmesan: "Parmesan"
        case .pineNut: "Pine nut"
        case .mortar: "Mortar"
        }
    }

    public var pairedIcon: AppIconChoice {
        switch self {
        case .basil: .basil
        case .parmesan: .parmesan
        case .pineNut: .pineNut
        case .mortar: .mortar
        }
    }

    /// The accent drawn on this theme's ground. Each pair reads as text (4.5:1) on the tinted ground of its own
    /// appearance, which `AppThemeTests` checks.
    public func accentHex(dark: Bool) -> String {
        switch self {
        case .basil: dark ? BrandPalette.accentDark : BrandPalette.accentLight
        case .parmesan: dark ? BrandPalette.goldTextDark : BrandPalette.goldTextLight
        case .pineNut: dark ? "E2A15E" : "8A4F16"
        case .mortar: dark ? "B9CDBF" : "3F5446"
        }
    }

    /// The wash over the shelf's glass, or nil for none. A wash, never a recolour: the glass stays visible.
    public func tint(dark: Bool) -> Tint? {
        switch (self, dark) {
        case (.basil, _): nil
        case (.parmesan, false): Tint(hex: BrandPalette.parmesan, opacity: 0.55)
        case (.parmesan, true): Tint(hex: BrandPalette.goldTextDark, opacity: 0.06)
        case (.pineNut, false): Tint(hex: BrandPalette.pineNut, opacity: 0.45)
        case (.pineNut, true): Tint(hex: BrandPalette.pineNut, opacity: 0.07)
        case (.mortar, false): Tint(hex: "7A90A8", opacity: 0.20)
        case (.mortar, true): Tint(hex: "000408", opacity: 0.60)
        }
    }

    /// The plain ground of the appearance with this theme's wash over it: what its accent and text must read on.
    public func groundHex(dark: Bool) -> String {
        let base = dark ? BrandPalette.darkSurface : BrandPalette.garlic
        guard let tint = tint(dark: dark) else { return base }
        return ContrastRatio.blend(tint.hex, over: base, alpha: tint.opacity)
    }

    /// What choosing this theme writes: the theme, its icon, and the accent put back on the brand colour (which is
    /// the theme's own accent).
    public func applied() -> Applied {
        Applied(theme: rawValue, icon: pairedIcon.rawValue, accent: AccentChoice.defaultStored)
    }
}
