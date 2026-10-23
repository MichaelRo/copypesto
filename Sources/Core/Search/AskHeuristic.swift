// SPDX-License-Identifier: MIT
import Foundation

/// Whether the search text reads like a request in words ("links from slack last week") rather than a term to look
/// for. It decides whether the Ask button is offered, and whether Return asks when a search finds nothing; Return
/// otherwise pastes the focused result, and ⌘Return always asks.
public enum AskHeuristic {
    private static let intentWords: Set<String> = [
        "what", "which", "where", "when", "who", "how", "find", "show", "get", "search", "give", "list",
        "today", "yesterday", "week", "month", "recent", "recently", "ago", "last", "from",
        "link", "links", "url", "urls", "image", "images", "picture", "pictures", "screenshot", "screenshots",
        "photo", "photos", "code", "snippet", "snippets", "file", "files", "document", "documents", "color", "colors"
    ]

    public static func looksLikeQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasSuffix("?") { return true }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        if words.count >= 3 { return true }
        return words.count == 2 && words.contains(where: intentWords.contains)
    }

    public static func returnAsks(text: String, resultCount: Int) -> Bool {
        resultCount == 0 && looksLikeQuestion(text)
    }
}
