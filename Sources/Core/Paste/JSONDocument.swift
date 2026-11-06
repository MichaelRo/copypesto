// SPDX-License-Identifier: MIT
import Foundation

/// A copied JSON object or array written with two-space indent and nothing else changed: keys keep their order and
/// numbers keep every digit (`JSONSerialization` sorts keys and turns a 20-digit id into a rounded double).
/// `JSONSerialization` only checks that the text is a document; the bytes are laid out here.
public enum JSONDocument {
    public static let maxInputBytes = 1_000_000
    public static let maxOutputBytes = 5_000_000

    /// Nil when the text is not one JSON object or array, is over the limits, or is already written this way, so the
    /// entry is offered only when it changes something.
    public static func formatted(_ text: String, maxOutputBytes: Int = JSONDocument.maxOutputBytes) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.utf8.first, first == UInt8(ascii: "{") || first == UInt8(ascii: "["),
              trimmed.utf8.count <= maxInputBytes, trimmed.utf8.count > 2 else { return nil }
        let bytes = Array(trimmed.utf8)
        guard (try? JSONSerialization.jsonObject(with: Data(bytes))) != nil,
              let laidOut = layout(bytes, maxBytes: maxOutputBytes) else { return nil }
        let result = String(validating: laidOut, as: UTF8.self) ?? ""
        return result == trimmed ? nil : result
    }

    private static func layout(_ bytes: [UInt8], maxBytes: Int) -> [UInt8]? {
        var writer = Writer(bytes: bytes)
        while writer.index < bytes.count {
            guard writer.step() else { return nil }
            if writer.out.count > maxBytes { return nil }
        }
        return writer.out
    }

    private struct Writer {
        let bytes: [UInt8]
        var out: [UInt8] = []
        var depth = 0
        var index = 0
        var inString = false
        var escaped = false

        init(bytes: [UInt8]) {
            self.bytes = bytes
            out.reserveCapacity(bytes.count + bytes.count / 4)
        }

        /// Writes the next byte; false when the text breaks a rule Foundation's parser lets through.
        mutating func step() -> Bool {
            let byte = bytes[index]
            index += 1
            if inString {
                insideString(byte)
                return true
            }
            switch byte {
            case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"):
                break
            case UInt8(ascii: "\""):
                inString = true
                out.append(byte)
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                opening(byte)
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                newline()
                out.append(byte)
            case UInt8(ascii: ","):
                // Foundation's parser accepts a comma before a closing bracket; JSON does not.
                if let next = nextNonSpace(from: index),
                   next.byte == UInt8(ascii: "}") || next.byte == UInt8(ascii: "]")
                {
                    return false
                }
                out.append(byte)
                newline()
            case UInt8(ascii: ":"):
                out.append(contentsOf: [byte, UInt8(ascii: " ")])
            default:
                out.append(byte)
            }
            return true
        }

        private mutating func insideString(_ byte: UInt8) {
            out.append(byte)
            if escaped {
                escaped = false
            } else if byte == UInt8(ascii: "\\") {
                escaped = true
            } else if byte == UInt8(ascii: "\"") {
                inString = false
            }
        }

        /// An empty object or array stays on one line.
        private mutating func opening(_ byte: UInt8) {
            out.append(byte)
            let close: UInt8 = byte == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
            if let next = nextNonSpace(from: index), next.byte == close {
                out.append(close)
                index = next.index + 1
            } else {
                depth += 1
                newline()
            }
        }

        private mutating func newline() {
            out.append(UInt8(ascii: "\n"))
            out.append(contentsOf: repeatElement(UInt8(ascii: " "), count: depth * 2))
        }

        private func nextNonSpace(from start: Int) -> (index: Int, byte: UInt8)? {
            var next = start
            while next < bytes.count {
                let byte = bytes[next]
                if byte != UInt8(ascii: " "), byte != UInt8(ascii: "\n"), byte != UInt8(ascii: "\r"),
                   byte != UInt8(ascii: "\t")
                {
                    return (next, byte)
                }
                next += 1
            }
            return nil
        }
    }
}
