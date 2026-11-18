// SPDX-License-Identifier: MIT
import Foundation

/// The query side of search by meaning, shared by the Mac shelf and the iPhone and iPad library: which queries ask for
/// it, which clips are near enough, and how they follow the text matches.
public enum SemanticSearch {
    public static let threshold: Float = 0.7
    public static let minimumQueryLength = 8
    public static let typingPause: Duration = .milliseconds(180)

    /// A plain query longer than eight characters; an `@` query is the source-app syntax.
    public static func asksForMeaning(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        return query.count > minimumQueryLength && !query.hasPrefix("@")
    }

    /// The clips whose vector is near the query's, nearest first.
    public static func rank(queryEmbedding: Data, candidates: [(id: UUID, embedding: Data?)]) -> [UUID] {
        candidates
            .compactMap { candidate -> (UUID, Float)? in
                guard let data = candidate.embedding else { return nil }
                let similarity = SemanticIndexer.cosineSimilarity(queryEmbedding, data)
                return similarity >= threshold ? (candidate.id, similarity) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// The text matches in their order, then the clips found by meaning that are allowed and not already there.
    public static func merged(textMatches: [UUID], byMeaning: [UUID], allowed: Set<UUID>) -> [UUID] {
        var present = Set(textMatches)
        var result = textMatches
        for id in byMeaning where allowed.contains(id) && present.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}
