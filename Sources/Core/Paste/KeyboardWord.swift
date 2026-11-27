// SPDX-License-Identifier: MIT
import Foundation

/// The word the person just typed on their own keyboard before switching to Pesto's, which the keyboard searches with
/// and replaces on insert, like text expansion (ADR 0062). Only the last word, only while the caret sits at its end
/// and the word ends in a letter or digit, without the punctuation before it; never kept: it is read from the field's
/// text each time.
public enum KeyboardWord {
    public struct Query: Equatable, Sendable {
        public let text: String
        public let isSelection: Bool

        public init(text: String, isSelection: Bool) {
            self.text = text
            self.isSelection = isSelection
        }
    }

    public static let minLength = 2
    public static let maxLength = 32

    /// Hybrid query: single-line selected text (when present and within `maxLength`) takes precedence over the word
    /// before the caret so replacing a selection inserts directly without extra deletes.
    public static func query(selected: String?, before contextBefore: String?, after contextAfter: String?) -> Query? {
        if let selected {
            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.count <= maxLength, !trimmed.contains(where: \.isNewline) {
                return Query(text: trimmed, isSelection: true)
            }
        }
        return before(contextBefore, after: contextAfter).map { Query(text: $0, isSelection: false) }
    }

    public static func before(_ text: String?, after: String?) -> String? {
        guard let text, let last = text.last, !last.isWhitespace else { return nil }
        if let next = after?.first, !next.isWhitespace { return nil }
        let token = text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        let word = String(token.drop { !isWordCharacter($0) })
        guard let end = word.last, isWordCharacter(end),
              (minLength...maxLength).contains(word.count) else { return nil }
        return word
    }

    /// How many times to press Delete to replace `word`, once per character as the caret moves over it, or nil when
    /// the field no longer ends with that word (the caret moved, or a clip was already put in its place).
    public static func deletions(replacing word: String, before text: String?, after: String?) -> Int? {
        before(text, after: after) == word ? word.count : nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
