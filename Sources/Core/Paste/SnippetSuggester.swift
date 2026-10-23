// SPDX-License-Identifier: MIT
import Foundation

/// A copied clip, as far as suggesting a snippet is concerned.
public struct SnippetCandidate: Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let pasteCount: Int
    public let isPinned: Bool
    public let isTextual: Bool
    public let isSecret: Bool

    public init(id: UUID, text: String, pasteCount: Int, isPinned: Bool, isTextual: Bool, isSecret: Bool) {
        self.id = id
        self.text = text
        self.pasteCount = pasteCount
        self.isPinned = isPinned
        self.isTextual = isTextual
        self.isSecret = isSecret
    }
}

/// Text you keep pasting is text worth keeping as a snippet. Only what was pasted from the shelf counts (copying the
/// same thing again is not tracked), and only ordinary text: never a secret, a picture, a clip that is already pinned
/// or one too short or long to be a template.
public enum SnippetSuggester {
    public static let minimumPastes = 3
    public static let textLengths = 8...2000

    public static func suggestions(from candidates: [SnippetCandidate], dismissed: Set<UUID> = [], limit: Int = 3)
    -> [SnippetCandidate] {
        candidates
            .filter { candidate in
                candidate.isTextual && !candidate.isSecret && !candidate.isPinned
                    && candidate.pasteCount >= minimumPastes
                    && textLengths.contains(candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).count)
                    && !dismissed.contains(candidate.id)
            }
            .sorted { $0.pasteCount > $1.pasteCount }
            .prefix(limit)
            .map(\.self)
    }
}
