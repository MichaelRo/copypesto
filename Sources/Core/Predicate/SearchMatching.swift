// SPDX-License-Identifier: MIT
import Foundation

/// The rule for matching typed text: folded for case and accents, then a substring. The shelf applies it to rows of the
/// history index (`HistoryIndex`), which `HistoryIndexParityTests` holds to this rule; these functions are the
/// reference.
public enum SearchMatching {
    /// Case- and diacritic-folded form used for matching. Folding is the expensive part, so callers that filter
    /// thousands of items per keystroke fold each text once (and cache it) and fold the query once.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public static func matches(_ text: String, query: String) -> Bool {
        query.isEmpty || fold(text).contains(fold(query))
    }

    public static func matches(foldedText: String, foldedQuery: String) -> Bool {
        foldedQuery.isEmpty || foldedText.contains(foldedQuery)
    }
}
