// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData

/// Clips that match a query by meaning, ranked off the main actor on a context of its own (every clip's sealed vector
/// is opened for it), and remembered for the same query over the same history.
@MainActor
final class SemanticRanking {
    private struct Memo {
        let query: String
        let revision: Int
        let ids: [UUID]
    }

    private var memo: Memo?
    private(set) var rankCount = 0

    func matches(
        for query: String, revision: Int, container: ModelContainer,
        embed: @escaping @Sendable (String) async -> Data? = SemanticRanking.deviceEmbedding
    ) async
    -> [UUID] {
        if let memo, memo.query == query, memo.revision == revision { return memo.ids }
        guard let embedding = await embed(query), !Task.isCancelled else { return [] }
        let ids = await Self.rank(queryEmbedding: embedding, container: container)
        guard !Task.isCancelled else { return [] }
        rankCount += 1
        memo = Memo(query: query, revision: revision, ids: ids)
        return ids
    }

    @Sendable
    nonisolated static func deviceEmbedding(_ text: String) async -> Data? {
        await SemanticIndexer.shared.embed(text: text)
    }

    @concurrent
    static func rank(queryEmbedding: Data, container: ModelContainer) async -> [UUID] {
        let context = ModelContext(container)
        guard let items = try? context.fetch(FetchDescriptor<ClipboardItem>()) else { return [] }
        return SemanticSearch.rank(
            queryEmbedding: queryEmbedding, candidates: items.map { ($0.id, $0.embeddingData) }
        )
    }
}
