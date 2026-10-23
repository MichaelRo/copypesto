// SPDX-License-Identifier: MIT
import Foundation

/// The colours a collection offers, and how a new collection picks one so two chips next to each other differ.
public enum CollectionPalette {
    public static let colors = [
        "007AFF", "FF3B30", "FF9500", "FFCC00",
        "34C759", "00C7BE", "5856D6", "AF52DE"
    ]

    /// The words for a swatch, so VoiceOver says "Blue" and not "Color 007AFF".
    public static let names = [
        "007AFF": "Blue", "FF3B30": "Red", "FF9500": "Orange", "FFCC00": "Yellow",
        "34C759": "Green", "00C7BE": "Teal", "5856D6": "Indigo", "AF52DE": "Purple"
    ]

    public static func name(forHex hex: String) -> String {
        names[normalized(hex)] ?? "Custom"
    }

    public static func normalized(_ hex: String) -> String {
        hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
    }

    public static func isSame(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    public static func isCustom(_ hex: String) -> Bool {
        !colors.contains { isSame($0, hex) }
    }

    public static func nextUnused(used: [String]) -> String {
        let taken = Set(used.map(normalized))
        if let free = colors.first(where: { !taken.contains($0) }) { return free }
        return colors[used.count % colors.count]
    }
}
