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
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.count >= 2, body.hasPrefix("\""), body.hasSuffix("\"") {
            body = String(body.dropFirst().dropLast())
        }
        let data = Data("\"\(body)\"".utf8)
        let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard let value = object as? String else { return nil }
        return value
    }

    static func backslashEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    static func backslashUnescape(_ text: String) -> String? {
        var result = ""
        var iterator = text.makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard let next = iterator.next() else { return nil }
            switch next {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "\\", "\"", "'": result.append(next)
            default: result.append("\\")
                result.append(next)
            }
        }
        return result
    }

    static func unicodeEscape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0..<0x80: result.unicodeScalars.append(scalar)
            case 0x80..<0x10000: result += String(format: "\\u%04x", scalar.value)
            default: result += "\\u{" + String(scalar.value, radix: 16) + "}"
            }
        }
        return result
    }

    private static let unicodeEscapePattern = try? NSRegularExpression(
        pattern: #"\\u(?:\{([0-9a-fA-F]{1,6})\}|([0-9a-fA-F]{4}))"#
    )

    static func unicodeUnescape(_ text: String) -> String? {
        guard let pattern = unicodeEscapePattern else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: whole)
        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { return nil }
            result += text[cursor..<range.lowerBound]
            let digitsRange = Range(match.range(at: 1), in: text) ?? Range(match.range(at: 2), in: text)
            guard let digitsRange, let value = UInt32(text[digitsRange], radix: 16),
                  let scalar = Unicode.Scalar(value) else { return nil }
            result.unicodeScalars.append(scalar)
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    static func htmlEncode(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let entityPattern = try? NSRegularExpression(pattern: "&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
    private static let namedEntities = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}"
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
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[name]
    }

    static func regexEscape(_ text: String) -> String {
        let metacharacters = Set("\\.*+?()[]{}|^$")
        return text.reduce(into: "") { result, character in
            if metacharacters.contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
