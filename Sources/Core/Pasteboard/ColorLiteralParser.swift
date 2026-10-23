// SPDX-License-Identifier: MIT
import Foundation

/// Finds the first colour written as `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`, `rgba()`, `hsl()` or `hsla()` in
/// a
/// text, with commas or with spaces and a slash before the alpha (`rgb(255 0 0 / 50%)`).
public enum ColorLiteralParser {
    public static func firstColor(in text: String) -> HexColorComponents? {
        hex(in: text) ?? rgb(in: text) ?? hsl(in: text)
    }

    /// True only when the whole text is one `rgb()`, `rgba()`, `hsl()` or `hsla()` colour with in-range numbers.
    /// A colour's preview is the one preview stored unencrypted (ADR 0002), so a wrapper around anything else
    /// (`rgb(password=…)`) is not a colour.
    public static func isFunctionalColor(_ text: String) -> Bool {
        // A colour is short: this check runs on every text copy, so a long text must not be searched for one (a 5 MB
        // clip took the budget of its ingest).
        guard text.utf16.count <= ColorPreviewPolicy.maximumLength * 2 else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count <= ColorPreviewPolicy.maximumLength, !trimmed.contains(where: \.isNewline),
              trimmed.lowercased().hasPrefix("rgb") || trimmed.lowercased().hasPrefix("hsl") else { return false }
        let whole = NSRange(trimmed.startIndex..., in: trimmed)
        let spansAll = { (regex: NSRegularExpression?) -> Bool in
            regex?.firstMatch(in: trimmed, range: whole)?.range == whole
        }
        if spansAll(rgbPattern) { return rgb(in: trimmed) != nil }
        if spansAll(hslPattern) { return hsl(in: trimmed) != nil }
        return false
    }

    /// `#178` and `&#178;` are an issue number and an HTML entity far more often than a colour, so a hash that follows
    /// a word character or an ampersand is skipped, and so are the shapes `HexColorParser.isAmbiguousShorthand` names
    /// (`#000`, `#999`, `#ffff` and `#f008` stay).
    private static let hexPattern = try? NSRegularExpression(
        pattern: #"(?<![\w&])#([0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{3,4})\b"#
    )

    private static func hex(in text: String) -> HexColorComponents? {
        guard let hexPattern else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for match in hexPattern.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text),
                  let digits = Range(match.range(at: 1), in: text) else { continue }
            if HexColorParser.isAmbiguousShorthand(text[digits]) { continue }
            if let color = HexColorParser.parse(String(text[range])) { return color }
        }
        return nil
    }

    private static let channel = #"(\d{1,3}(?:\.\d+)?%?)"#
    private static let separator = #"(?:\s*,\s*|\s+)"#
    private static let alpha = #"(?:\s*[,/]\s*(\d*\.?\d+%?))?"#
    private static let rgbPattern = try? NSRegularExpression(
        pattern: #"rgba?\(\s*"# + channel + separator + channel + separator + channel + alpha + #"\s*\)"#,
        options: [.caseInsensitive]
    )
    private static let hslPattern = try? NSRegularExpression(
        pattern: #"hsla?\(\s*(\d+(?:\.\d+)?)(?:deg)?"# + separator + #"(\d+(?:\.\d+)?)%"# + separator
            + #"(\d+(?:\.\d+)?)%"# + alpha + #"\s*\)"#,
        options: [.caseInsensitive]
    )

    private static func groups(of regex: NSRegularExpression?, in text: String) -> [String?]? {
        guard let regex, let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }

    /// A channel as a fraction: `50%` is half, a plain number is out of `scale`. Nil when it is out of range.
    private static func fraction(_ text: String, scale: Double) -> Double? {
        let isPercent = text.hasSuffix("%")
        guard let value = Double(isPercent ? String(text.dropLast()) : text) else { return nil }
        let result = isPercent ? value / 100 : value / scale
        return (0...1).contains(result) ? result : nil
    }

    private static func alphaValue(_ text: String?) -> Double {
        guard let text else { return 1 }
        let isPercent = text.hasSuffix("%")
        guard let value = Double(isPercent ? String(text.dropLast()) : text) else { return 1 }
        return min(max(isPercent ? value / 100 : value, 0), 1)
    }

    private static func rgb(in text: String) -> HexColorComponents? {
        guard let parts = groups(of: rgbPattern, in: text), parts.count == 4,
              let red = parts[0].flatMap({ fraction($0, scale: 255) }),
              let green = parts[1].flatMap({ fraction($0, scale: 255) }),
              let blue = parts[2].flatMap({ fraction($0, scale: 255) }) else { return nil }
        return HexColorComponents(red: red, green: green, blue: blue, alpha: alphaValue(parts[3]))
    }

    private static func hsl(in text: String) -> HexColorComponents? {
        guard let parts = groups(of: hslPattern, in: text), parts.count == 4,
              let hueDegrees = parts[0].flatMap(Double.init),
              let saturationPercent = parts[1].flatMap(Double.init), saturationPercent <= 100,
              let lightnessPercent = parts[2].flatMap(Double.init), lightnessPercent <= 100 else { return nil }
        let hue = hueDegrees.truncatingRemainder(dividingBy: 360) / 360
        let saturation = saturationPercent / 100
        let lightness = lightnessPercent / 100
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let second = chroma * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1))
        let offset = lightness - chroma / 2
        let base: [Double] = switch Int(hue * 6) {
        case 0: [chroma, second, 0]
        case 1: [second, chroma, 0]
        case 2: [0, chroma, second]
        case 3: [0, second, chroma]
        case 4: [second, 0, chroma]
        default: [chroma, 0, second]
        }
        return HexColorComponents(
            red: base[0] + offset, green: base[1] + offset, blue: base[2] + offset, alpha: alphaValue(parts[3])
        )
    }
}
