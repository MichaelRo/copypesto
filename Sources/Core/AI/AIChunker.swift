// SPDX-License-Identifier: MIT
import Foundation

/// One part of a long text: the text the model reads, and where it sits in the clip (1-based, inclusive characters).
public struct AIPart: Sendable, Equatable {
    public let text: String
    public let start: Int
    public let end: Int
}

/// The parts of a text, and how much of the clip they cover.
public struct AIParts: Sendable, Equatable {
    public let parts: [AIPart]
    /// The characters in the whole clip.
    public let total: Int
    /// The characters the parts can reach: the whole clip, or `AIChunker.maxCharacters` of it.
    public let readable: Int

    public var isCut: Bool {
        readable < total
    }

    public init(parts: [AIPart], total: Int, readable: Int) {
        self.parts = parts
        self.total = total
        self.readable = readable
    }
}

/// Cuts a long text into parts for a summary read one part at a time (`docs/design/ai-chunked-summary.md`). With
/// `AIInput.make` it is the only place text is cut for the model. Only the first `maxCharacters` are ever copied, so a
/// 5 MB
/// clip costs no more than a 100,000-character one.
public enum AIChunker {
    /// The most characters of a clip that are read, however large the model's window is.
    public static let maxCharacters = 100_000

    public static func parts(
        of text: String, budget: Int, totalCharacters: Int? = nil, maxCharacters: Int = AIChunker.maxCharacters
    )
    -> AIParts {
        let total = max(totalCharacters ?? text.count, 0)
        let characters = Array(text.prefix(maxCharacters))
        let readable = min(max(total, characters.count), maxCharacters)
        var parts: [AIPart] = []
        var start = 0
        while start < characters.count {
            let end = characters.count - start <= budget ? characters.count : cut(
                characters,
                from: start,
                budget: budget
            )
            let part = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { parts.append(AIPart(text: part, start: start + 1, end: end)) }
            start = end
        }
        return AIParts(parts: parts, total: max(total, characters.count), readable: readable)
    }

    /// Where the part that starts at `start` ends: after the last blank line, sentence end, line end or whitespace in
    /// the
    /// second half of its budget, in that order, or at the budget when there is none (one very long word).
    private static func cut(_ characters: [Character], from start: Int, budget: Int) -> Int {
        let limit = start + budget
        let floor = start + budget / 2
        let searches: [(Int) -> Bool] = [
            { $0 > start && characters[$0] == "\n" && characters[$0 - 1] == "\n" },
            { index in
                index + 1 < limit && ".!?\u{2026}".contains(characters[index]) && characters[index + 1].isWhitespace
            },
            { characters[$0] == "\n" },
            { characters[$0].isWhitespace }
        ]
        for matches in searches {
            var index = limit - 1
            while index >= floor {
                if matches(index) { return index + 1 }
                index -= 1
            }
        }
        return limit
    }
}
