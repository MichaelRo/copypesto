// SPDX-License-Identifier: MIT
import Foundation

/// The recent searches shown when the search field is empty, stored as one string in preferences.
public enum SearchHistory {
    public static let defaultsKey = Setting.searchHistory.name
    static let separator = "|||"
    static let limit = 10

    public static func entries(from raw: String) -> [String] {
        raw.components(separatedBy: separator).filter { !$0.isEmpty }
    }

    /// The stored string after `query` is searched: newest first, no duplicates, at most `limit` entries.
    public static func recording(_ query: String, in raw: String) -> String {
        let cleaned = query.replacingOccurrences(of: separator, with: " ").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return raw }
        // A pasted card number or token typed into search must not sit in plaintext preferences.
        guard SensitiveContentDetector.detectAnywhere(in: cleaned) == nil else { return raw }
        let kept = entries(from: raw).filter { $0 != cleaned }
        return ([cleaned] + kept).prefix(limit).joined(separator: separator)
    }
}
