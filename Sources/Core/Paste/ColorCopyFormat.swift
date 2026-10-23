// SPDX-License-Identifier: MIT
import Foundation

/// The forms a colour clip can be copied as from its Copy As menu.
public enum ColorCopyFormat: CaseIterable, Sendable {
    case hex
    case hexNoHash
    case rgb
    case hsl
    case cmyk
    case oklch
    case swiftUI
    case nsColor

    public var title: String {
        switch self {
        case .hex: "HEX"
        case .hexNoHash: "HEX (no #)"
        case .rgb: "RGB"
        case .hsl: "HSL"
        case .cmyk: "CMYK"
        case .oklch: "OKLCH"
        case .swiftUI: "SwiftUI Color"
        case .nsColor: "NSColor"
        }
    }

    public func string(for color: HexColorComponents) -> String {
        let bytes = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
        let opaque = color.alpha >= 0.999
        switch self {
        case .hex:
            let alphaByte = Int((color.alpha * 255).rounded())
            let digits = bytes.map { String(format: "%02X", $0) }.joined()
            return "#" + digits + (opaque ? "" : String(format: "%02X", alphaByte))
        case .hexNoHash:
            let alphaByte = Int((color.alpha * 255).rounded())
            let digits = bytes.map { String(format: "%02X", $0) }.joined()
            return digits + (opaque ? "" : String(format: "%02X", alphaByte))
        case .rgb:
            let list = bytes.map(String.init).joined(separator: ", ")
            return opaque ? "rgb(\(list))" : "rgba(\(list), \(Self.number(color.alpha, places: 2)))"
        case .hsl:
            let parts = Self.hsl(color)
            let list = "\(parts[0]), \(parts[1])%, \(parts[2])%"
            return opaque ? "hsl(\(list))" : "hsla(\(list), \(Self.number(color.alpha, places: 2)))"
        case .cmyk:
            let parts = Self.cmyk(color)
            return "cmyk(\(parts[0])%, \(parts[1])%, \(parts[2])%, \(parts[3])%)"
        case .oklch:
            let oklchColor = Self.oklch(color)
            let base = "\(Self.number(oklchColor.lightness, places: 3)) "
                + "\(Self.number(oklchColor.chroma, places: 3)) "
                + "\(Self.number(oklchColor.hue, places: 1))"
            return opaque ? "oklch(\(base))" : "oklch(\(base) / \(Self.number(color.alpha, places: 2)))"
        case .swiftUI:
            let list = Self.components(color)
            return "Color(red: \(list.red), green: \(list.green), blue: \(list.blue)"
                + (opaque ? ")" : ", opacity: \(Self.number(color.alpha, places: 2)))")
        case .nsColor:
            let list = Self.components(color)
            return "NSColor(srgbRed: \(list.red), green: \(list.green), blue: \(list.blue), alpha: "
                + (opaque ? "1" : Self.number(color.alpha, places: 2)) + ")"
        }
    }

    private struct Components {
        let red: String
        let green: String
        let blue: String
    }

    private static func components(_ color: HexColorComponents) -> Components {
        Components(
            red: number(color.red, places: 3), green: number(color.green, places: 3), blue: number(
                color.blue,
                places: 3
            )
        )
    }

    /// A short decimal: `0.5`, not `0.500`, and `1`, not `1.000`.
    private static func number(_ value: Double, places: Int) -> String {
        var text = String(format: "%.\(places)f", value)
        while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }

    private static func hsl(_ color: HexColorComponents) -> [Int] {
        let (red, green, blue) = (color.red, color.green, color.blue)
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let lightness = (high + low) / 2
        let spread = high - low
        guard spread > 0 else { return [0, 0, Int((lightness * 100).rounded())] }
        let saturation = spread / (1 - abs(2 * lightness - 1))
        var hue: Double = switch high {
        case red: ((green - blue) / spread).truncatingRemainder(dividingBy: 6)
        case green: (blue - red) / spread + 2
        default: (red - green) / spread + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return [Int(hue.rounded()) % 360, Int((saturation * 100).rounded()), Int((lightness * 100).rounded())]
    }

    private static func cmyk(_ color: HexColorComponents) -> [Int] {
        let (red, green, blue) = (color.red, color.green, color.blue)
        let black = 1.0 - max(red, green, blue)
        guard black < 0.9999 else { return [0, 0, 0, 100] }
        let cyan = (1.0 - red - black) / (1.0 - black)
        let magenta = (1.0 - green - black) / (1.0 - black)
        let yellow = (1.0 - blue - black) / (1.0 - black)
        return [
            Int((cyan * 100).rounded()),
            Int((magenta * 100).rounded()),
            Int((yellow * 100).rounded()),
            Int((black * 100).rounded())
        ]
    }

    private static func srgbToLinear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private struct OklchComponents {
        let lightness: Double
        let chroma: Double
        let hue: Double
    }

    private static func oklch(_ color: HexColorComponents) -> OklchComponents {
        let linearRed = srgbToLinear(color.red)
        let linearGreen = srgbToLinear(color.green)
        let linearBlue = srgbToLinear(color.blue)

        let lmsL = 0.4122214708 * linearRed + 0.5363325363 * linearGreen + 0.0514459929 * linearBlue
        let lmsM = 0.2119034982 * linearRed + 0.6806995451 * linearGreen + 0.1073969566 * linearBlue
        let lmsS = 0.0883024619 * linearRed + 0.2817188376 * linearGreen + 0.6299787005 * linearBlue

        let cubicL = cbrt(lmsL)
        let cubicM = cbrt(lmsM)
        let cubicS = cbrt(lmsS)

        let oklabL = 0.2104542553 * cubicL + 0.7936177850 * cubicM - 0.0040720468 * cubicS
        let oklabA = 1.9779984951 * cubicL - 2.4285922050 * cubicM + 0.4505937099 * cubicS
        let oklabB = 0.0259040371 * cubicL + 0.7827717662 * cubicM - 0.8086757660 * cubicS

        let chroma = sqrt(oklabA * oklabA + oklabB * oklabB)
        var hue: Double = 0
        if chroma >= 0.0005 {
            hue = atan2(oklabB, oklabA) * 180.0 / .pi
            if hue < 0 { hue += 360 }
        }
        return OklchComponents(lightness: max(0, min(1, oklabL)), chroma: chroma, hue: hue)
    }
}
