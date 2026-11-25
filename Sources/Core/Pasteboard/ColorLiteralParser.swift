// SPDX-License-Identifier: MIT
import Foundation

/// Parses `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, bare `RRGGBB`/`RRGGBBAA` (whole-string only), and CSS functional
/// colours (`rgb()`, `rgba()`, `hsl()`, `hsla()`, `oklch()`, `oklab()`, `hwb()`, `color(srgb|srgb-linear|display-p3)`,
/// `cmyk()`).
public enum ColorLiteralParser {
    /// Finds the first `#`-hex or functional colour literal anywhere in `text`. Bare hex without `#` is ignored in
    /// prose so words and hashes do not false-positive.
    public static func firstColor(in text: String) -> HexColorComponents? {
        // Card previews are capped well below 4096 characters; scanning only a prefix prevents multi-MB pastes from
        // running every colour pattern across the full string.
        let limit = ColorPreviewPolicy.maximumLength * 64
        let scan = text.count > limit ? String(text.prefix(limit)) : text
        var earliest: (location: Int, color: HexColorComponents)?
        func consider(_ candidate: (location: Int, color: HexColorComponents)?) {
            guard let candidate else { return }
            if earliest == nil || candidate.location < (earliest?.location ?? .max) {
                earliest = candidate
            }
        }
        consider(firstHexMatch(in: scan))
        for parser in functionalParsers {
            consider(firstMatch(using: parser, in: scan))
        }
        return earliest?.color
    }

    /// Parses `text` only when the entire trimmed single-line string is one colour literal, including standalone
    /// bare 6/8-character hex matching `ContentClassifier`'s mixed digit-and-letter policy.
    public static func color(fromWholeString text: String) -> HexColorComponents? {
        guard text.utf16.count <= ColorPreviewPolicy.maximumLength * 2 else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
        if trimmed.hasPrefix("#") {
            let whole = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = hexPattern?.firstMatch(in: trimmed, range: whole),
                  match.range == whole,
                  let digits = Range(match.range(at: 1), in: trimmed),
                  !HexColorParser.isAmbiguousShorthand(trimmed[digits]) else { return nil }
            return HexColorParser.parse(trimmed)
        }
        let whole = NSRange(trimmed.startIndex..., in: trimmed)
        if let bareMatch = bareHexPattern?.firstMatch(in: trimmed, range: whole),
           bareMatch.range == whole,
           !(trimmed.allSatisfy(\.isASCII) && trimmed.allSatisfy(\.isNumber)),
           !trimmed.allSatisfy(\.isLetter)
        {
            return HexColorParser.parse(trimmed)
        }
        return parseWholeFunctionalColor(trimmed)
    }

    /// True only when the whole text is one strict functional colour literal with in-range numeric channels.
    /// A colour's preview is the one preview stored unencrypted (ADR 0002), so wrappers like `oklch(password=...)`
    /// never qualify.
    public static func isFunctionalColor(_ text: String) -> Bool {
        guard text.utf16.count <= ColorPreviewPolicy.maximumLength * 2 else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count <= ColorPreviewPolicy.maximumLength, !trimmed.contains(where: \.isNewline) else {
            return false
        }
        return parseWholeFunctionalColor(trimmed) != nil
    }

    // MARK: - Hex patterns

    private static let hexPattern = try? NSRegularExpression(
        pattern: #"(?<![\w&])#([0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{3,4})\b"#
    )
    private static let bareHexPattern = try? NSRegularExpression(
        pattern: #"^[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?$"#
    )

    private static func firstHexMatch(in text: String) -> (location: Int, color: HexColorComponents)? {
        guard let hexPattern else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for match in hexPattern.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text),
                  let digits = Range(match.range(at: 1), in: text) else { continue }
            if HexColorParser.isAmbiguousShorthand(text[digits]) { continue }
            if let color = HexColorParser.parse(String(text[range])) {
                return (match.range.location, color)
            }
        }
        return nil
    }

    // MARK: - Functional patterns

    private struct FunctionalParser {
        let prefixes: [String]
        let regex: NSRegularExpression?
        let parse: @Sendable ([String?]) -> HexColorComponents?
    }

    private static let separator = #"(?:\s*,\s*|\s+)"#
    private static let unsignedChannel = #"((?:\d+(?:\.\d*)?|\.\d+)%?)"#
    private static let signedChannel = #"([+-]?(?:\d+(?:\.\d*)?|\.\d+)%?)"#
    private static let angleToken = #"([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:deg|rad|grad|turn)?)"#
    private static let percentToken = #"(\d+(?:\.\d+)?)%"#
    private static let commaOrSlashAlpha = #"(?:\s*[,/]\s*((?:\d+(?:\.\d*)?|\.\d+)%?))?"#
    private static let slashAlpha = #"(?:\s*/\s*((?:\d+(?:\.\d*)?|\.\d+)%?))?"#
    private static let boundary = #"(?<![A-Za-z0-9_-])"#

    private static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: boundary + pattern, options: [.caseInsensitive])
    }

    private static let functionalParsers: [FunctionalParser] = [
        FunctionalParser(
            prefixes: ["rgb(", "rgba("],
            regex: makeRegex(
                #"rgba?\(\s*"# + unsignedChannel + separator + unsignedChannel + separator
                    + unsignedChannel + commaOrSlashAlpha + #"\s*\)"#
            ),
            parse: parseRGB
        ),
        FunctionalParser(
            prefixes: ["hsl(", "hsla("],
            regex: makeRegex(
                #"hsla?\(\s*"# + angleToken + separator + percentToken + separator
                    + percentToken + commaOrSlashAlpha + #"\s*\)"#
            ),
            parse: parseHSL
        ),
        FunctionalParser(
            prefixes: ["oklch("],
            regex: makeRegex(
                #"oklch\(\s*"# + unsignedChannel + #"\s+"# + unsignedChannel + #"\s+"#
                    + angleToken + slashAlpha + #"\s*\)"#
            ),
            parse: parseOKLCH
        ),
        FunctionalParser(
            prefixes: ["oklab("],
            regex: makeRegex(
                #"oklab\(\s*"# + unsignedChannel + #"\s+"# + signedChannel + #"\s+"#
                    + signedChannel + slashAlpha + #"\s*\)"#
            ),
            parse: parseOKLAB
        ),
        FunctionalParser(
            prefixes: ["hwb("],
            regex: makeRegex(
                #"hwb\(\s*"# + angleToken + #"\s+"# + percentToken + #"\s+"#
                    + percentToken + slashAlpha + #"\s*\)"#
            ),
            parse: parseHWB
        ),
        FunctionalParser(
            prefixes: ["color("],
            regex: makeRegex(
                #"color\(\s*(srgb|srgb-linear|display-p3)\s+"# + unsignedChannel + #"\s+"#
                    + unsignedChannel + #"\s+"# + unsignedChannel + slashAlpha + #"\s*\)"#
            ),
            parse: parseColorSpace
        ),
        FunctionalParser(
            prefixes: ["cmyk("],
            regex: makeRegex(
                #"cmyk\(\s*"# + percentToken + separator + percentToken + separator
                    + percentToken + separator + percentToken + slashAlpha + #"\s*\)"#
            ),
            parse: parseCMYK
        )
    ]

    private static func parseWholeFunctionalColor(_ trimmed: String) -> HexColorComponents? {
        let lower = trimmed.lowercased()
        let whole = NSRange(trimmed.startIndex..., in: trimmed)
        for parser in functionalParsers where parser.prefixes.contains(where: { lower.hasPrefix($0) }) {
            guard let regex = parser.regex,
                  let match = regex.firstMatch(in: trimmed, range: whole),
                  match.range == whole else { continue }
            return parser.parse(groups(of: match, in: trimmed))
        }
        return nil
    }

    private static func firstMatch(
        using parser: FunctionalParser, in text: String
    )
    -> (location: Int, color: HexColorComponents)? {
        guard let regex = parser.regex else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: whole) {
            if let color = parser.parse(groups(of: match, in: text)) {
                return (match.range.location, color)
            }
        }
        return nil
    }

    private static func groups(of match: NSTextCheckingResult, in text: String) -> [String?] {
        (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }

    // MARK: - Component helpers

    private static func fraction(_ text: String, scale: Double) -> Double? {
        let isPercent = text.hasSuffix("%")
        guard let value = Double(isPercent ? String(text.dropLast()) : text), value.isFinite else { return nil }
        let result = isPercent ? value / 100 : value / scale
        return (0...1).contains(result) ? result : nil
    }

    private static func signedOKLabComponent(_ text: String) -> Double? {
        let isPercent = text.hasSuffix("%")
        guard let value = Double(isPercent ? String(text.dropLast()) : text), value.isFinite else { return nil }
        let scaled = isPercent ? (value / 100.0) * 0.4 : value
        return (-0.5...0.5).contains(scaled) ? scaled : nil
    }

    private static func alphaValue(_ text: String?) -> Double {
        guard let text else { return 1 }
        let isPercent = text.hasSuffix("%")
        guard let value = Double(isPercent ? String(text.dropLast()) : text), value.isFinite else { return 1 }
        return min(max(isPercent ? value / 100 : value, 0), 1)
    }

    private static func parseHueDegrees(_ raw: String) -> Double? {
        let lower = raw.lowercased()
        let numberText: String
        let scale: Double
        if lower.hasSuffix("grad") {
            numberText = String(lower.dropLast(4))
            scale = 0.9
        } else if lower.hasSuffix("rad") {
            numberText = String(lower.dropLast(3))
            scale = 180.0 / .pi
        } else if lower.hasSuffix("deg") {
            numberText = String(lower.dropLast(3))
            scale = 1.0
        } else if lower.hasSuffix("turn") {
            numberText = String(lower.dropLast(4))
            scale = 360.0
        } else {
            numberText = lower
            scale = 1.0
        }
        guard let value = Double(numberText), value.isFinite else { return nil }
        let scaled = value * scale
        guard scaled.isFinite else { return nil }
        var wrapped = scaled.truncatingRemainder(dividingBy: 360.0)
        guard wrapped.isFinite else { return nil }
        if wrapped < 0 { wrapped += 360.0 }
        return wrapped
    }

    // MARK: - Individual schemas

    private static func parseRGB(_ parts: [String?]) -> HexColorComponents? {
        guard parts.count == 4,
              let red = parts[0].flatMap({ fraction($0, scale: 255) }),
              let green = parts[1].flatMap({ fraction($0, scale: 255) }),
              let blue = parts[2].flatMap({ fraction($0, scale: 255) }) else { return nil }
        return HexColorComponents(red: red, green: green, blue: blue, alpha: alphaValue(parts[3]))
    }

    private static func parseHSL(_ parts: [String?]) -> HexColorComponents? {
        guard parts.count == 4,
              let hueDegrees = parts[0].flatMap(parseHueDegrees),
              let saturationPercent = parts[1].flatMap(Double.init), saturationPercent <= 100,
              let lightnessPercent = parts[2].flatMap(Double.init), lightnessPercent <= 100 else { return nil }
        let rgb = hslToRGB(
            hueDegrees: hueDegrees,
            saturation: saturationPercent / 100,
            lightness: lightnessPercent / 100
        )
        guard rgb.red.isFinite, rgb.green.isFinite, rgb.blue.isFinite else { return nil }
        return HexColorComponents(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alphaValue(parts[3]))
    }

    private static func parseOKLCH(_ parts: [String?]) -> HexColorComponents? {
        guard parts.count == 4,
              let lightness = parts[0].flatMap({ fraction($0, scale: 1) }),
              let chromaStr = parts[1],
              let hueDegrees = parts[2].flatMap(parseHueDegrees) else { return nil }
        let isPercent = chromaStr.hasSuffix("%")
        guard let rawChroma = Double(isPercent ? String(chromaStr.dropLast()) : chromaStr),
              rawChroma.isFinite else { return nil }
        let chroma = isPercent ? (rawChroma / 100.0) * 0.4 : rawChroma
        guard (0...0.5).contains(chroma) else { return nil }
        let radians = hueDegrees * .pi / 180.0
        return oklabToSRGB(
            lightness: lightness,
            a: chroma * cos(radians),
            b: chroma * sin(radians),
            alpha: alphaValue(parts[3])
        )
    }

    private static func parseOKLAB(_ parts: [String?]) -> HexColorComponents? {
        guard parts.count == 4,
              let lightness = parts[0].flatMap({ fraction($0, scale: 1) }),
              let a = parts[1].flatMap(signedOKLabComponent),
              let b = parts[2].flatMap(signedOKLabComponent) else { return nil }
        return oklabToSRGB(lightness: lightness, a: a, b: b, alpha: alphaValue(parts[3]))
    }

    private static func parseHWB(_ parts: [String?]) -> HexColorComponents? {
        guard parts.count == 4,
              let hueDegrees = parts[0].flatMap(parseHueDegrees),
              let whitePercent = parts[1].flatMap(Double.init), whitePercent <= 100,
              let blackPercent = parts[2].flatMap(Double.init), blackPercent <= 100 else { return nil }
        let whiteness = whitePercent / 100.0
        let blackness = blackPercent / 100.0
        let alpha = alphaValue(parts[3])
        if whiteness + blackness >= 1.0 {
            let gray = whiteness / (whiteness + blackness)
            return HexColorComponents(red: gray, green: gray, blue: gray, alpha: alpha)
        }
        let hueRGB = hslToRGB(hueDegrees: hueDegrees, saturation: 1.0, lightness: 0.5)
        guard hueRGB.red.isFinite, hueRGB.green.isFinite, hueRGB.blue.isFinite else { return nil }
        let scale = 1.0 - whiteness - blackness
        return HexColorComponents(
            red: hueRGB.red * scale + whiteness,
            green: hueRGB.green * scale + whiteness,
            blue: hueRGB.blue * scale + whiteness,
            alpha: alpha
        )
    }

    private static func parseColorSpace(_ parts: [String?]) -> HexColorComponents? {
        guard parts.count == 5,
              let space = parts[0]?.lowercased(),
              let c1 = parts[1].flatMap({ fraction($0, scale: 1) }),
              let c2 = parts[2].flatMap({ fraction($0, scale: 1) }),
              let c3 = parts[3].flatMap({ fraction($0, scale: 1) }) else { return nil }
        let alpha = alphaValue(parts[4])
        switch space {
        case "srgb":
            return HexColorComponents(red: c1, green: c2, blue: c3, alpha: alpha)
        case "srgb-linear":
            return HexColorComponents(
                red: linearToSRGB(c1),
                green: linearToSRGB(c2),
                blue: linearToSRGB(c3),
                alpha: alpha
            )
        case "display-p3":
            let pr = srgbToLinear(c1)
            let pg = srgbToLinear(c2)
            let pb = srgbToLinear(c3)
            let x = 0.4865709486482162 * pr + 0.26566769316909306 * pg + 0.1982172852343625 * pb
            let y = 0.2289745640697488 * pr + 0.6917385218365064 * pg + 0.079286914093745 * pb
            let z = 0.04511338185890264 * pg + 1.043944368900976 * pb
            let linR = 3.2409699419045213 * x - 1.5373831775700935 * y - 0.4986107602930033 * z
            let linG = -0.9692436362808798 * x + 1.8759675015077206 * y + 0.04155505740717561 * z
            let linB = 0.05563007969699361 * x - 0.20397695888897657 * y + 1.0569715142428786 * z
            return HexColorComponents(
                red: linearToSRGB(min(max(linR, 0), 1)),
                green: linearToSRGB(min(max(linG, 0), 1)),
                blue: linearToSRGB(min(max(linB, 0), 1)),
                alpha: alpha
            )
        default:
            return nil
        }
    }

    private static func parseCMYK(_ parts: [String?]) -> HexColorComponents? {
        guard parts.count == 5,
              let cyan = parts[0].flatMap(Double.init), cyan <= 100,
              let magenta = parts[1].flatMap(Double.init), magenta <= 100,
              let yellow = parts[2].flatMap(Double.init), yellow <= 100,
              let black = parts[3].flatMap(Double.init), black <= 100 else { return nil }
        let k = black / 100.0
        return HexColorComponents(
            red: (1.0 - cyan / 100.0) * (1.0 - k),
            green: (1.0 - magenta / 100.0) * (1.0 - k),
            blue: (1.0 - yellow / 100.0) * (1.0 - k),
            alpha: alphaValue(parts[4])
        )
    }
}

private extension ColorLiteralParser {
    // MARK: - Color math

    struct RGBChannels {
        let red: Double
        let green: Double
        let blue: Double
    }

    static func hslToRGB(
        hueDegrees: Double,
        saturation: Double,
        lightness: Double
    )
    -> RGBChannels {
        let hue = hueDegrees / 360.0
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let second = chroma * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1))
        let offset = lightness - chroma / 2
        let base = switch Int(hue * 6) {
        case 0: RGBChannels(red: chroma, green: second, blue: 0)
        case 1: RGBChannels(red: second, green: chroma, blue: 0)
        case 2: RGBChannels(red: 0, green: chroma, blue: second)
        case 3: RGBChannels(red: 0, green: second, blue: chroma)
        case 4: RGBChannels(red: second, green: 0, blue: chroma)
        default: RGBChannels(red: chroma, green: 0, blue: second)
        }
        return RGBChannels(red: base.red + offset, green: base.green + offset, blue: base.blue + offset)
    }

    static func oklabToSRGB(lightness: Double, a: Double, b: Double, alpha: Double) -> HexColorComponents? {
        guard lightness.isFinite, a.isFinite, b.isFinite else { return nil }
        var candidate = linearSRGBFromOKLab(lightness: lightness, a: a, b: b)
        let tolerance = -0.0005...1.0005
        if !(tolerance.contains(candidate.red)
            && tolerance.contains(candidate.green)
            && tolerance.contains(candidate.blue))
        {
            var low = 0.0
            var high = 1.0
            for _ in 0..<14 {
                let mid = (low + high) * 0.5
                let probe = linearSRGBFromOKLab(lightness: lightness, a: a * mid, b: b * mid)
                if (0...1).contains(probe.red), (0...1).contains(probe.green), (0...1).contains(probe.blue) {
                    low = mid
                    candidate = probe
                } else {
                    high = mid
                }
            }
        }
        guard candidate.red.isFinite, candidate.green.isFinite, candidate.blue.isFinite else { return nil }
        return HexColorComponents(
            red: linearToSRGB(min(max(candidate.red, 0), 1)),
            green: linearToSRGB(min(max(candidate.green, 0), 1)),
            blue: linearToSRGB(min(max(candidate.blue, 0), 1)),
            alpha: alpha
        )
    }

    static func linearSRGBFromOKLab(lightness: Double, a: Double, b: Double) -> RGBChannels {
        let lPrime = lightness + 0.3963377774 * a + 0.2158037573 * b
        let mPrime = lightness - 0.1055613458 * a - 0.0638541728 * b
        let sPrime = lightness - 0.0894841775 * a - 1.2914855480 * b

        let lCubed = lPrime * lPrime * lPrime
        let mCubed = mPrime * mPrime * mPrime
        let sCubed = sPrime * sPrime * sPrime

        return RGBChannels(
            red: +4.0767416621 * lCubed - 3.3077115913 * mCubed + 0.2309699292 * sCubed,
            green: -1.2684380046 * lCubed + 2.6097574011 * mCubed - 0.3413193965 * sCubed,
            blue: -0.0041960863 * lCubed - 0.7034186147 * mCubed + 1.7076147010 * sCubed
        )
    }

    static func srgbToLinear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    static func linearToSRGB(_ channel: Double) -> Double {
        channel <= 0.0031308 ? 12.92 * channel : 1.055 * pow(channel, 1.0 / 2.4) - 0.055
    }
}
