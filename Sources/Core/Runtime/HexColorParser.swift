// SPDX-License-Identifier: MIT
import Foundation

public struct HexColorComponents: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var luminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

public enum HexColorParser {
    /// The digits after a hash that are an issue number, a status code or a hashtag more often than a colour. A
    /// colour's
    /// preview is the one preview stored unencrypted (ADR 0002), so these stay text.
    /// - Three or four digits that differ (`#178`, `#1234`).
    /// - Four hex characters with no digit that are not all the same (`#cafe`, `#face`); `#ffff` and `#f008` stay
    /// colours.
    public static func isAmbiguousShorthand(_ digits: some StringProtocol) -> Bool {
        guard digits.count == 3 || digits.count == 4 else { return false }
        let distinct = Set(digits.lowercased()).count > 1
        let allDigits = digits.allSatisfy { $0.isASCII && $0.isNumber }
        if allDigits { return distinct }
        return digits.count == 4 && distinct && !digits.contains { $0.isASCII && $0.isNumber }
    }

    public static func parse(_ hex: String) -> HexColorComponents? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        switch cleaned.count {
        case 3:
            guard let rgb = UInt32(cleaned, radix: 16) else { return nil }
            let r = ((rgb >> 8) & 0xF) * 0x11
            let g = ((rgb >> 4) & 0xF) * 0x11
            let b = (rgb & 0xF) * 0x11
            return HexColorComponents(
                red: Double(r) / 255.0,
                green: Double(g) / 255.0,
                blue: Double(b) / 255.0,
                alpha: 1.0
            )
        case 4:
            guard let rgba = UInt32(cleaned, radix: 16) else { return nil }
            return HexColorComponents(
                red: Double(((rgba >> 12) & 0xF) * 0x11) / 255.0,
                green: Double(((rgba >> 8) & 0xF) * 0x11) / 255.0,
                blue: Double(((rgba >> 4) & 0xF) * 0x11) / 255.0,
                alpha: Double((rgba & 0xF) * 0x11) / 255.0
            )
        case 6:
            guard let rgb = UInt64(cleaned, radix: 16) else { return nil }
            return HexColorComponents(
                red: Double((rgb >> 16) & 0xFF) / 255.0,
                green: Double((rgb >> 8) & 0xFF) / 255.0,
                blue: Double(rgb & 0xFF) / 255.0,
                alpha: 1.0
            )
        case 8:
            guard let rgba = UInt64(cleaned, radix: 16) else { return nil }
            return HexColorComponents(
                red: Double((rgba >> 24) & 0xFF) / 255.0,
                green: Double((rgba >> 16) & 0xFF) / 255.0,
                blue: Double((rgba >> 8) & 0xFF) / 255.0,
                alpha: Double(rgba & 0xFF) / 255.0
            )
        default:
            return nil
        }
    }
}
