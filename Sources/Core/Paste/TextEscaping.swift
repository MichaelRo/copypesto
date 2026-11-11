// SPDX-License-Identifier: MIT
import Foundation

enum TextEscaping {
    static func jsonEscape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func jsonUnescape(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String = if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            String(trimmed.dropFirst().dropLast())
        } else {
            text
        }
        let data = Data("\"\(body)\"".utf8)
        let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard let value = object as? String else { return nil }
        return value
    }

    static func backslashEscape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func backslashUnescape(_ text: String) -> String? {
        var result = ""
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            guard scalar == "\\" else {
                result.unicodeScalars.append(scalar)
                continue
            }
            guard let next = iterator.next() else { return nil }
            switch next {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "\\", "\"", "'": result.unicodeScalars.append(next)
            default:
                result.append("\\")
                result.unicodeScalars.append(next)
            }
        }
        return result
    }

    static func unicodeEscape(_ text: String) -> String {
        var result = ""
        for unit in text.utf16 {
            if unit < 0x80, let scalar = Unicode.Scalar(unit) {
                result.unicodeScalars.append(scalar)
            } else {
                result += String(format: "\\u%04x", unit)
            }
        }
        return result
    }

    static func unicodeUnescape(_ text: String) -> String? {
        let scalars = Array(text.unicodeScalars)
        var result = ""
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "\\" else {
                result.unicodeScalars.append(scalars[index])
                index += 1
                continue
            }
            if index + 1 < scalars.count, scalars[index + 1] == "\\" {
                result += "\\\\"
                index += 2
                continue
            }
            guard index + 1 < scalars.count, scalars[index + 1] == "u" else {
                result.append("\\")
                index += 1
                continue
            }
            guard let parsed = parseUnicodeEscape(scalars, from: index) else { return nil }
            result.unicodeScalars.append(parsed.scalar)
            index = parsed.nextIndex
        }
        return result
    }

    private static func parseUnicodeEscape(
        _ scalars: [Unicode.Scalar], from index: Int
    )
    -> (scalar: Unicode.Scalar, nextIndex: Int)? {
        let afterU = index + 2
        guard afterU < scalars.count else { return nil }
        if scalars[afterU] == "{" {
            guard let close = scalars[(afterU + 1)...].firstIndex(of: "}") else { return nil }
            let count = close - (afterU + 1)
            guard (1...6).contains(count),
                  let value = parseHex(scalars[(afterU + 1)..<close]),
                  let scalar = Unicode.Scalar(value) else { return nil }
            return (scalar, close + 1)
        }
        guard afterU + 4 <= scalars.count,
              let unit = parseHex(scalars[afterU..<(afterU + 4)]) else { return nil }
        let afterFirst = afterU + 4
        if (0xD800...0xDBFF).contains(unit) {
            guard afterFirst + 6 <= scalars.count,
                  scalars[afterFirst] == "\\", scalars[afterFirst + 1] == "u",
                  let low = parseHex(scalars[(afterFirst + 2)..<(afterFirst + 6)]),
                  (0xDC00...0xDFFF).contains(low) else { return nil }
            let combined = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
            guard let scalar = Unicode.Scalar(combined) else { return nil }
            return (scalar, afterFirst + 6)
        }
        guard let scalar = Unicode.Scalar(unit) else { return nil }
        return (scalar, afterFirst)
    }

    private static func parseHex(_ slice: ArraySlice<Unicode.Scalar>) -> UInt32? {
        var hex = ""
        for scalar in slice {
            guard ("0"..."9").contains(scalar) || ("a"..."f").contains(scalar) || ("A"..."F").contains(scalar) else {
                return nil
            }
            hex.unicodeScalars.append(scalar)
        }
        return UInt32(hex, radix: 16)
    }

    static func htmlEncode(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static let entityPattern = try? NSRegularExpression(pattern: "&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
    private static let namedEntities = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bull": "•", "middot": "·",
        "laquo": "«", "raquo": "»", "times": "×", "divide": "÷", "plusmn": "±",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "deg": "°", "sect": "§", "para": "¶",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓"
    ]

    static func htmlDecode(_ text: String) -> String {
        guard let pattern = entityPattern else { return text }
        var result = ""
        var cursor = text.startIndex
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let body = Range(match.range(at: 1), in: text) else {
                continue
            }
            let name = String(text[body])
            guard let replacement = entity(name) else { continue }
            result += text[cursor..<range.lowerBound]
            result += replacement
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    private static func entity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first.map { $0 == "x" || $0 == "X" } == true
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            guard let value, value > 0, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[name]
    }

    static func regexEscape(_ text: String) -> String {
        let metacharacters: Set<Unicode.Scalar> = [
            "\\",
            ".",
            "*",
            "+",
            "?",
            "(",
            ")",
            "[",
            "]",
            "{",
            "}",
            "|",
            "^",
            "$"
        ]
        var result = ""
        for scalar in text.unicodeScalars {
            if metacharacters.contains(scalar) { result.append("\\") }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    static func shellQuote(_ text: String) -> String {
        var result = "'"
        for scalar in text.unicodeScalars {
            if scalar == "'" {
                result += "'\\''"
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        result.append("'")
        return result
    }
}
