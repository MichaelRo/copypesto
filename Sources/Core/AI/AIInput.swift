// SPDX-License-Identifier: MIT
import Foundation

/// The part of a clip's text the model is given, and how much of the clip that is.
public struct AIInput: Sendable, Equatable {
    public let text: String
    public let coverage: AIResult.Coverage

    /// `totalCharacters` is the length of the whole clip when `full` is only the start of it (the 500-character
    /// preview); leave it nil when `full` is the whole text.
    public static func make(_ full: String, budget: Int, totalCharacters: Int? = nil) -> AIInput {
        let total = max(totalCharacters ?? full.count, full.count)
        guard full.count > budget else {
            return AIInput(text: full, coverage: .init(shown: full.count, total: total))
        }
        let head = full.prefix(budget)
        let atBoundary = head.lastIndex(where: \.isWhitespace).map { head[..<$0] } ?? head
        let cut = atBoundary.isEmpty ? head : atBoundary
        return AIInput(text: String(cut), coverage: .init(shown: cut.count, total: total))
    }
}

/// How many characters of a clip one request may carry. The model's window is counted in tokens, which are shorter than
/// characters in code and in most languages other than English, so the factor is conservative.
public enum AIInputBudget {
    static let fallback = 8000
    static let reservedTokens = 1200
    static let charactersPerToken = 3
    static let range = 4000...40_000

    public static func characters(contextTokens: Int?) -> Int {
        guard let contextTokens else { return fallback }
        let fit = max(0, contextTokens - reservedTokens) * charactersPerToken
        return min(max(fit, range.lowerBound), range.upperBound)
    }
}
