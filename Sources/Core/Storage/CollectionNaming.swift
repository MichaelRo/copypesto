// SPDX-License-Identifier: MIT
import Foundation

/// Collection names are unique, as folder names are in Finder: a name that is taken gets the lowest free number
/// ("Work 2", "Work 3"), so creating, duplicating and renaming never fail or leave two chips that look alike.
public enum CollectionNaming {
    public static let defaultName = "New Collection"

    /// `excluding` is the name of the collection being renamed, which does not clash with itself.
    public static func uniqueName(_ proposed: String, existing: [String], excluding: String? = nil) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? defaultName : trimmed
        var taken = Set(existing.map(key))
        if let excluding { taken.remove(key(excluding)) }
        guard taken.contains(key(base)) else { return base }
        var number = 2
        while taken.contains(key("\(base) \(number)")) {
            number += 1
        }
        return "\(base) \(number)"
    }

    public static func copyName(of source: String, existing: [String]) -> String {
        uniqueName("\(source) Copy", existing: existing)
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
