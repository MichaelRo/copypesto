// SPDX-License-Identifier: MIT
import Foundation

/// The visible text of a copied HTML fragment, read without a browser engine: nothing the markup names is ever
/// requested. One pass over the bytes, so hostile input costs time in proportion to its size.
public enum HTMLText {
    public static func plainText(from data: Data) -> String {
        // Latin-1 reads any byte, so markup that is not UTF-8 still gives its text; from here on the bytes are valid
        // UTF-8.
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        var reader = Reader(bytes: Array(html.utf8))
        reader.run()
        return reader.output
    }

    private static let droppedElements: Set<String> = ["script", "style", "head", "title", "template", "noscript"]
    private static let paragraphElements: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "table", "blockquote", "pre", "hr", "dl"
    ]
    private static let lineElements: Set<String> = [
        "div", "li", "tr", "section", "article", "header", "footer", "nav", "main", "aside", "dt", "dd", "figure",
        "figcaption", "form", "fieldset", "address", "details", "summary"
    ]

    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        var text: [UInt8] = []
        var output = ""
        var pendingBreaks = 0
        var pendingSpace = false

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func run() {
            while index < bytes.count {
                let byte = bytes[index]
                guard byte == UInt8(ascii: "<") else {
                    text.append(byte)
                    index += 1
                    continue
                }
                if !readMarkup() { break }
            }
            flushText()
        }

        /// False when the rest of the input is unusable (an unterminated tag or comment).
        private mutating func readMarkup() -> Bool {
            if matches("<!--", at: index) {
                guard let end = find("-->", from: index + 4) else { return false }
                flushText()
                index = end + 3
                return true
            }
            var cursor = index + 1
            let closing = cursor < bytes.count && bytes[cursor] == UInt8(ascii: "/")
            if closing { cursor += 1 }
            let nameStart = cursor
            while cursor < bytes.count, isNameByte(bytes[cursor]) {
                cursor += 1
            }
            guard cursor > nameStart || (cursor < bytes.count && bytes[cursor] == UInt8(ascii: "!")) else {
                text.append(bytes[index]) // "a < b" is text
                index += 1
                return true
            }
            let name = (String(bytes: bytes[nameStart..<cursor], encoding: .utf8) ?? "").lowercased()
            guard let tagEnd = endOfTag(from: cursor) else { return false }
            flushText()
            index = tagEnd + 1
            if !closing, droppedElements.contains(name) {
                guard let close = findClosing(name, from: index) else { return false }
                index = close
                return true
            }
            noteBreak(for: name)
            return true
        }

        private mutating func noteBreak(for name: String) {
            if name == "br" {
                pendingBreaks = min(pendingBreaks + 1, 2)
            } else if paragraphElements.contains(name) {
                pendingBreaks = 2
            } else if lineElements.contains(name) {
                pendingBreaks = max(pendingBreaks, 1)
            } else if name == "td" || name == "th" {
                pendingSpace = true
            }
        }

        /// The index of the `>` that ends the tag, skipping any inside a quoted attribute value.
        private func endOfTag(from start: Int) -> Int? {
            var quote: UInt8?
            var cursor = start
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if let open = quote {
                    if byte == open { quote = nil }
                } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                    quote = byte
                } else if byte == UInt8(ascii: ">") {
                    return cursor
                }
                cursor += 1
            }
            return nil
        }

        /// The index just after the `>` of the end tag of `name`, matched without regard to case.
        private func findClosing(_ name: String, from start: Int) -> Int? {
            let pattern = Array("</\(name)".utf8)
            var cursor = start
            while cursor + pattern.count <= bytes.count {
                if bytes[cursor] == UInt8(ascii: "<"), matchesIgnoringCase(pattern, at: cursor),
                   let end = endOfTag(from: cursor + pattern.count)
                {
                    return end + 1
                }
                cursor += 1
            }
            return nil
        }

        private func matches(_ literal: String, at position: Int) -> Bool {
            let pattern = Array(literal.utf8)
            guard position + pattern.count <= bytes.count else { return false }
            return pattern.indices.allSatisfy { bytes[position + $0] == pattern[$0] }
        }

        private func matchesIgnoringCase(_ pattern: [UInt8], at position: Int) -> Bool {
            pattern.indices.allSatisfy { lowercased(bytes[position + $0]) == pattern[$0] }
        }

        private func find(_ literal: String, from start: Int) -> Int? {
            let pattern = Array(literal.utf8)
            var cursor = start
            while cursor + pattern.count <= bytes.count {
                if matches(literal, at: cursor) { return cursor }
                cursor += 1
            }
            return nil
        }

        private func lowercased(_ byte: UInt8) -> UInt8 {
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
        }

        private func isNameByte(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
        }

        private mutating func flushText() {
            guard !text.isEmpty else { return }
            let decoded = HTMLEntities.decode(String(bytes: text, encoding: .utf8) ?? "")
            text.removeAll(keepingCapacity: true)
            for character in decoded {
                if character.isWhitespace {
                    pendingSpace = true
                    continue
                }
                if pendingBreaks > 0 {
                    if !output.isEmpty { output += String(repeating: "\n", count: pendingBreaks) }
                } else if pendingSpace, !output.isEmpty, output.last != "\n" {
                    output.append(" ")
                }
                pendingBreaks = 0
                pendingSpace = false
                output.append(character)
            }
        }
    }
}

enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "copy": "\u{A9}", "reg": "\u{AE}",
        "trade": "\u{2122}", "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}", "lsquo": "\u{2018}",
        "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bull": "\u{2022}", "middot": "\u{B7}",
        "euro": "\u{20AC}", "pound": "\u{A3}", "yen": "\u{A5}", "cent": "\u{A2}", "deg": "\u{B0}", "times": "\u{D7}",
        "divide": "\u{F7}", "laquo": "\u{AB}", "raquo": "\u{BB}", "para": "\u{B6}", "sect": "\u{A7}",
        "larr": "\u{2190}", "rarr": "\u{2192}", "uarr": "\u{2191}", "darr": "\u{2193}"
    ]

    /// Replaces the entities it knows and leaves every other `&` as it was.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = text[...]
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let afterAmpersand = rest.index(after: ampersand)
            let window = rest[afterAmpersand...].prefix(12)
            guard let semicolon = window.firstIndex(of: ";"),
                  let replacement = value(of: window[..<semicolon]) else
            {
                result.append("&")
                rest = rest[afterAmpersand...]
                continue
            }
            result += replacement
            rest = rest[rest.index(after: semicolon)...]
        }
        return result + rest
    }

    private static func value(of body: Substring) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let isHex = digits.first == "x" || digits.first == "X"
            guard let code = UInt32(isHex ? digits.dropFirst() : digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(code) else { return nil }
            return String(Character(scalar))
        }
        return named[String(body)]
    }
}
