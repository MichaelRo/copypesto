// SPDX-License-Identifier: MIT
import Foundation

/// The word the person just typed on their own keyboard before switching to Pesto's, which the keyboard searches with
/// and replaces on insert, like text expansion (ADR 0062). Only the last word, only while the caret sits at its end
/// and the word ends in a letter or digit, without the punctuation before it; never kept: it is read from the field's
/// text each time.
public enum KeyboardWord {
    public static let minLength = 2
    public static let maxLength = 32

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
