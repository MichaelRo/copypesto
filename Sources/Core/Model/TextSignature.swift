// SPDX-License-Identifier: MIT
import Foundation

/// A fixed-size MinHash of a text's word shingles: two texts that share most of their words in order have signatures
/// that agree in about that share of positions (ADR 0017). It is derived data, sealed wherever it is stored, and tells
/// nothing a reader without the key could use.
public struct TextSignature: Equatable, Sendable {
    public static let width = 64
    public static let minimumWords = 6

    public let values: [UInt32]

    public init(values: [UInt32]) {
        precondition(values.count == Self.width)
        self.values = values
    }

    /// Nil when the text is too short to compare.
    public static func make(from text: String) -> TextSignature? {
        let words = normalizedWords(in: text)
        guard words.count >= minimumWords else { return nil }
        let size = words.count < 30 ? 2 : 3
        var minima = [UInt32](repeating: .max, count: width)
        var window: [UInt64] = []
        window.reserveCapacity(size)
        for start in 0...(words.count - size) {
            var hash: UInt64 = 0xCBF2_9CE4_8422_2325
            for word in words[start..<(start + size)] {
                hash = (hash ^ word) &* 0x0000_0100_0000_01B3
                hash = (hash ^ (hash >> 29)) &* 0xBF58_476D_1CE4_E5B9
            }
            var state = hash
            for slot in 0..<width {
                state = (state &+ 0x9E37_79B9_7F4A_7C15) ^ (state >> 31)
                let mixed = (state ^ (state >> 33)) &* 0xFF51_AFD7_ED55_8CCD
                let value = UInt32(truncatingIfNeeded: mixed >> 32)
                if value < minima[slot] { minima[slot] = value }
            }
        }
        return TextSignature(values: minima)
    }

    /// The share of positions where the two agree: an estimate of the overlap of the two texts' shingles.
    public func similarity(to other: TextSignature) -> Double {
        var same = 0
        for slot in 0..<Self.width where values[slot] == other.values[slot] {
            same += 1
        }
        return Double(same) / Double(Self.width)
    }

    /// Lowercased words, every run of digits read as one `#` so an order number or a date does not set two copies of the
    /// same message apart.
    static func normalizedWords(in text: String) -> [UInt64] {
        var words: [UInt64] = []
        var current: UInt64 = 0xCBF2_9CE4_8422_2325
        var inWord = false
        var inDigits = false
        func flush() {
            if inWord { words.append(current) }
            current = 0xCBF2_9CE4_8422_2325
            inWord = false
            inDigits = false
        }
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if scalar.properties.numericType != nil {
                    if inDigits { continue }
                    inDigits = true
                    current = (current ^ 0x23) &* 0x0000_0100_0000_01B3
                } else {
                    inDigits = false
                    for lowered in String(scalar).lowercased().unicodeScalars {
                        current = (current ^ UInt64(lowered.value)) &* 0x0000_0100_0000_01B3
                    }
                }
                inWord = true
            } else {
                flush()
            }
        }
        flush()
        return words
    }
}
