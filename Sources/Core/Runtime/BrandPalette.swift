// SPDX-License-Identifier: MIT
import Foundation

public enum BrandPalette {
    public static let accentLight = "2F7A49"
    public static let accentDark = "6DBE85"
    public static let garlic = "FAF7EE"
    public static let parmesan = "F6EFD9"
    public static let mortar = "2B2F2A"
    public static let darkSurface = "1F2320"
    public static let goldTextLight = "7A5F00"
    public static let goldTextDark = "E3C04A"
    public static let goldFill = "C9A227"
    public static let pineNut = "EBD9B4"
    public static let stone = "7A7466"
}

/// A named accent in Settings → Appearance. Each has a darker shade for light surfaces and a lighter one for dark, both
/// readable as text (4.5:1) on the plain light and dark grounds; `AccentPresetTests` checks it.
public enum AccentPreset: String, CaseIterable, Sendable {
    case blue
    case purple
    case pink
    case red
    case orange
    case graphite

    public var displayName: String {
        rawValue.capitalized
    }

    public func hex(dark: Bool) -> String {
        switch self {
        case .blue: dark ? "5EA3FF" : "0B5FD8"
        case .purple: dark ? "C08BFF" : "7A3FC0"
        case .pink: dark ? "FF7AA2" : "C2185B"
        case .red: dark ? "FF7B72" : "C62828"
        case .orange: dark ? "FF8A3D" : "BD4F00"
        case .graphite: dark ? "98A4C0" : "5A6478"
        }
    }

    /// The system colours earlier versions stored as a hex; they map to the preset that replaced them.
    static func migrating(hex: String) -> AccentPreset? {
        switch hex.uppercased() {
        case "0A84FF": .blue
        case "BF5AF2": .purple
        case "FF375F": .pink
        case "FF9F0A": .orange
        default: nil
        }
    }
}

/// What Settings → Appearance stores in `accentColorHex`: a fresh install gets the theme's own accent (`brand`), a
/// preset is stored by name, and a six-digit hex is a colour they chose. An empty string, the old "system accent", is
/// the theme's accent now: it only ever drew the system's blue, because Pesto declares no accent of its own.
public enum AccentChoice: Equatable, Sendable {
    case brand
    case preset(AccentPreset)
    case custom(String)

    public static let defaultStored = "brand"

    public init(stored: String) {
        if stored.isEmpty || stored == Self.defaultStored {
            self = .brand
        } else if let preset = AccentPreset(rawValue: stored) ?? AccentPreset.migrating(hex: stored) {
            self = .preset(preset)
        } else {
            let hex = stored.uppercased()
            self = ContrastRatio.luminance(hex: hex) == nil ? .brand : .custom(hex)
        }
    }

    /// The value to store for this choice.
    public var stored: String {
        switch self {
        case .brand: Self.defaultStored
        case let .preset(preset): preset.rawValue
        case let .custom(hex): hex
        }
    }
}

public enum ContrastRatio {
    /// WCAG 2.x contrast ratio; 0 when either colour is not a six-digit hex.
    public static func between(_ first: String, _ second: String) -> Double {
        guard let a = luminance(hex: first), let b = luminance(hex: second) else { return 0 }
        let (lighter, darker) = (max(a, b), min(a, b))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// White or the dark brand ink, whichever reads better on an accent-coloured button fill. White on the dark-mode
    /// basil (`6DBE85`) is about 2:1.
    public static func labelHex(onFill fill: String) -> String {
        let white = "FFFFFF"
        guard luminance(hex: fill) != nil else { return white }
        return between(white, fill) >= between(BrandPalette.mortar, fill) ? white : BrandPalette.mortar
    }

    /// `hex` moved toward black (light ground) or white (dark ground) just far enough to read as text on `ground`; the
    /// colour itself when it already does. A preset on another theme's tinted ground, or an accent the person chose,
    /// is the case it covers.
    public static func readable(_ hex: String, on ground: String, minimum: Double = 4.5, darkGround: Bool) -> String {
        guard luminance(hex: hex) != nil, between(hex, ground) < minimum else { return hex }
        let toward = darkGround ? "FFFFFF" : "000000"
        var candidate = hex
        for step in 1...25 {
            candidate = blend(toward, over: hex, alpha: Double(step) * 0.04)
            if between(candidate, ground) >= minimum { return candidate }
        }
        return candidate
    }

    /// `foreground` painted at `alpha` over `background`, as a hex string (for checking text on a tinted fill).
    public static func blend(_ foreground: String, over background: String, alpha: Double) -> String {
        guard let top = UInt32(foreground, radix: 16),
              let bottom = UInt32(background, radix: 16) else { return background }
        func channel(_ value: UInt32, _ shift: UInt32) -> Double {
            Double((value >> shift) & 0xFF)
        }
        func mixed(_ shift: UInt32) -> Int {
            Int((channel(top, shift) * alpha + channel(bottom, shift) * (1 - alpha)).rounded())
        }
        return String(format: "%02X%02X%02X", mixed(16), mixed(8), mixed(0))
    }

    static func luminance(hex: String) -> Double? {
        HexColorParser.parse(hex)?.luminance
    }
}

/// The garlic-into-parmesan ground the website draws behind its hero, with a basil glow low on the left and a gold one
/// high on the right, as the Mac app draws it behind onboarding. Colours only; the view is `BrandBackdropView`.
public enum BrandBackdrop {
    public struct Glow: Equatable, Sendable {
        public let hex: String
        public let opacity: Double
    }

    public static let basilGlow = Glow(hex: "529D6E", opacity: 0.30)
    public static let goldGlow = Glow(hex: BrandPalette.goldFill, opacity: 0.14)

    /// Top to bottom.
    public static func stops(dark: Bool) -> [String] {
        dark
            ? [BrandPalette.darkSurface, BrandPalette.darkSurface, BrandPalette.mortar]
            : [BrandPalette.garlic, BrandPalette.parmesan, BrandPalette.parmesan]
    }
}
