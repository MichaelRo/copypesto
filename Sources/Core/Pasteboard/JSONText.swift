// SPDX-License-Identifier: MIT
import Foundation

/// A copy that is one JSON object or array, so `@json` finds it and the card shows it as code.
enum JSONText {
    static let language = "json"
    /// Parsing is linear, but a big copy is not worth reading twice: past this it is plain text.
    static let maxCharacters = 100_000

    static func isJSONDocument(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "{" || first == "[", trimmed.utf8.count <= maxCharacters,
              trimmed.count > 2 else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }
}
