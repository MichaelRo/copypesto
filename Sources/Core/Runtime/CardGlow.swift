// SPDX-License-Identifier: MIT
import Foundation

/// The foot glow (ADR 0068): the source app's color rising from a card's foot to 40% of its height, so a clip says
/// where it came from without a band or a border. The sampled icon color is normalized in OKLCH (its hue kept,
/// lightness fixed per appearance, chroma capped) so every app glows at the same strength; a hue near basil (focus) or
/// gold (collections) is muted, and a near-neutral icon draws nothing. In dark the glow is deep (lightness 0.42, at
/// 12%), about the card's own lightness, so it tints the foot without lifting it: the panel's 0.74 at 16%, and even
/// 0.60, took the foot text under 4.5:1 on the Mac's Pine nut card (`CardMetaLineContrastTests`). Views draw `stops`.
public struct CardGlow: Equatable, Sendable {
    /// `RRGGBB`, no `#`.
    public let hex: String
    public let opacity: Double
    public let chroma: Double

    /// Location from the foot (0) toward the top, and the share of `opacity` drawn there.
    public static let stops: [(location: Double, share: Double)] = [(0, 1), (0.15, 0.55), (0.28, 0.18), (0.40, 0)]

    private static let basilHue = 152.0
    private static let goldHue = 90.0

    /// `themeAccentHex` is the glow of a card whose app gives no color (a near-neutral icon, a clip made on the
    /// iPhone, a snippet): the theme's own hue, always muted, so a theme is felt without saying anything about the
    /// clip (design board 5).
    public static func decide(
        colorHex: String?, themeAccentHex: String? = nil, isDark: Bool, isGlass: Bool, increaseContrast: Bool,
        isSelected: Bool
    )
    -> CardGlow? {
        guard !increaseContrast else { return nil }
        let fromApp = colorHex.flatMap(OKLCH.init(hex:)).flatMap { $0.isVivid ? $0 : nil }
        let fromTheme = themeAccentHex.flatMap(OKLCH.init(hex:)).flatMap { $0.chroma >= 0.02 ? $0 : nil }
        guard let sampled = fromApp ?? fromTheme else { return nil }
        let muted = fromApp == nil || near(sampled.hue, basilHue, within: 22) || near(sampled.hue, goldHue, within: 18)
        let chroma = min(sampled.chroma, muted ? 0.05 : 0.12)
        let base = isGlass ? (isDark ? 0.09 : 0.08) : (isDark ? 0.12 : 0.11)
        let opacity = base * (muted ? 0.7 : 1) * (isSelected ? 0.6 : 1)
        return CardGlow(
            hex: hex(lightness: isDark ? 0.42 : 0.70, chroma: chroma, hue: sampled.hue), opacity: opacity,
            chroma: chroma
        )
    }

    /// The card's ground where the glow is strongest, for checking text on it.
    public func blended(over ground: String) -> String? {
        let base = ground.hasPrefix("#") ? String(ground.dropFirst()) : ground
        return ContrastRatio.blend(hex, over: base, alpha: opacity)
    }

    /// An sRGB color, `RRGGBB`, for an OKLCH lightness, chroma and hue, clipped into the gamut.
    public static func hex(lightness: Double, chroma: Double, hue: Double) -> String {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let lCone = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let mCone = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let sCone = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        let linear = [
            4.0767416621 * lCone - 3.3077115913 * mCone + 0.2309699292 * sCone,
            -1.2684380046 * lCone + 2.6097574011 * mCone - 0.3413193965 * sCone,
            -0.0041960863 * lCone - 0.7034186147 * mCone + 1.7076147010 * sCone
        ]
        let bytes = linear.map { value -> Int in
            let clipped = min(max(value, 0), 1)
            let gamma = clipped <= 0.0031308 ? 12.92 * clipped : 1.055 * pow(clipped, 1 / 2.4) - 0.055
            return Int((gamma * 255).rounded())
        }
        return String(format: "%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }

    private static func near(_ hue: Double, _ center: Double, within width: Double) -> Bool {
        abs((hue - center + 540).truncatingRemainder(dividingBy: 360) - 180) <= width
    }

    private struct OKLCH {
        let lightness: Double
        let chroma: Double
        let hue: Double

        var isVivid: Bool {
            chroma >= 0.035 && lightness >= 0.25 && lightness <= 0.93
        }

        init?(hex: String) {
            let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
            func linear(_ shift: UInt32) -> Double {
                let channel = Double((value >> shift) & 0xFF) / 255
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            let (r, g, b) = (linear(16), linear(8), linear(0))
            let lCone = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let mCone = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let sCone = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            lightness = 0.2104542553 * lCone + 0.7936177850 * mCone - 0.0040720468 * sCone
            let a = 1.9779984951 * lCone - 2.4285922050 * mCone + 0.4505937099 * sCone
            let b2 = 0.0259040371 * lCone + 0.7827717662 * mCone - 0.8086757660 * sCone
            chroma = (a * a + b2 * b2).squareRoot()
            hue = (atan2(b2, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        }
    }
}
