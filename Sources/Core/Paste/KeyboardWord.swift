// SPDX-License-Identifier: MIT
import Foundation

/// The word the person just typed on their own keyboard before switching to Pesto's, which the keyboard searches with
/// and replaces on insert, like text expansion (ADR 0062). Only the last word, only while the caret sits at its end,
/// and never kept: it is read from the field's text each time.
public enum KeyboardWord {
    public static let minLength = 2
    public static let maxLength = 32

    public static func before(_ text: String?, after: String?) -> String? {
        guard let text, let last = text.last, !last.isWhitespace else { return nil }
        if let next = after?.first, !next.isWhitespace { return nil }
        let word = text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard (minLength...maxLength).contains(word.count) else { return nil }
        return word
    }

    /// How many times to press Delete to remove `word`: once per character as the caret moves over it.
    public static func deletions(for word: String) -> Int {
        word.count
    }
}
