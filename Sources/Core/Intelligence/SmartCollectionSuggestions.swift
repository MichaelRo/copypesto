// SPDX-License-Identifier: MIT
import Foundation
import NaturalLanguage

/// On-device k-means clustering of clipboard item embeddings to suggest pinboard groupings.
///
/// Runs entirely on-device — no network calls. Requires `embeddingData` populated by
/// `SemanticIndexer`. Items without embeddings are excluded from clustering.
public actor SmartCollectionSuggestions {
    public static let shared = SmartCollectionSuggestions()

    public struct Suggestion: Sendable {
        public let name: String
        public let itemIDs: [UUID]
        public let keyTerms: [String]
    }

    /// Input type for `suggest(items:k:)` — avoids a large-tuple API.
    public struct ItemInput: Sendable {
        public let id: UUID
        public let preview: String
        public let embedding: Data
        public init(id: UUID, preview: String, embedding: Data) {
            self.id = id
            self.preview = preview
            self.embedding = embedding
        }
    }

    /// Clusters `items` into up to `k` groups using k-means on their Float32 embedding vectors.
    /// Returns suggestions with auto-generated names (NLTagger keyword extraction).
    /// Items with no `embedding` data are silently excluded.
    public func suggest(items: [ItemInput], k: Int = 5) -> [Suggestion] {
        guard items.count >= k else { return [] }

        // Vectors of another length (from before a model change, or a bad restore) cannot be averaged with the rest:
        // only the most common length is clustered.
        let allVectors = items.map { floatVector(from: $0.embedding) }
        let lengths = Dictionary(grouping: allVectors.map(\.count).filter { $0 > 0 }, by: { $0 })
        guard let dim = lengths.max(by: { $0.value.count < $1.value.count })?.key else { return [] }
        let usable = allVectors.indices.filter { allVectors[$0].count == dim }
        guard usable.count >= k else { return [] }
        let items = usable.map { items[$0] }
        let floatVecs = usable.map { allVectors[$0] }

        let assignments = kMeans(vectors: floatVecs, k: k, maxIterations: 20)

        var clusters: [Int: [(id: UUID, preview: String)]] = [:]
        for (i, item) in items.enumerated() {
            let cluster = assignments[i]
            clusters[cluster, default: []].append((id: item.id, preview: item.preview))
        }

        return clusters.compactMap { _, members -> Suggestion? in
            guard members.count >= 2 else { return nil }
            let ids = members.map(\.id)
            let previews = members.prefix(5).map(\.preview)
            let terms = extractKeyTerms(from: previews)
            guard let topTerm = terms.first, !topTerm.isEmpty else { return nil }
            let name = topTerm.capitalized
            return Suggestion(name: name, itemIDs: ids, keyTerms: terms)
        }
        .filter { $0.itemIDs.count >= 2 }
        .sorted { $0.itemIDs.count > $1.itemIDs.count }
    }

    // MARK: - k-means

    private func kMeans(vectors: [[Float]], k: Int, maxIterations: Int) -> [Int] {
        let count = vectors.count
        guard count > 0, let dim = vectors.first?.count, dim > 0 else {
            return Array(repeating: 0, count: count)
        }
        let clampedK = min(k, count)

        var centroids: [[Float]] = stride(from: 0, to: count, by: max(1, count / clampedK))
            .prefix(clampedK)
            .map { vectors[$0] }
        if centroids.count < clampedK {
            centroids += Array(
                repeating: Array(repeating: 0, count: dim),
                count: clampedK - centroids.count
            )
        }

        var assignments = Array(repeating: 0, count: count)

        for _ in 0..<maxIterations {
            var changed = false
            for (i, vec) in vectors.enumerated() {
                let nearest = centroids.indices.min {
                    squaredDistance(vec, centroids[$0]) < squaredDistance(vec, centroids[$1])
                } ?? 0
                if assignments[i] != nearest { changed = true }
                assignments[i] = nearest
            }
            guard changed else { break }

            for j in 0..<clampedK {
                let members = assignments.indices.filter { assignments[$0] == j }
                guard !members.isEmpty else { continue }
                var newCentroid = Array(repeating: Float(0), count: dim)
                for idx in members {
                    for d in 0..<dim {
                        newCentroid[d] += vectors[idx][d]
                    }
                }
                let n = Float(members.count)
                centroids[j] = newCentroid.map { $0 / n }
            }
        }

        return assignments
    }

    private func squaredDistance(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { acc, pair in acc + (pair.0 - pair.1) * (pair.0 - pair.1) }
    }

    // MARK: - Keyword extraction

    private static let ignoredTerms: Set<String> = [
        "json", "func", "struct", "class", "async", "await", "test", "tests",
        "import", "return", "self", "init", "true", "false", "null", "file",
        "code", "line", "item", "data", "error", "view", "state", "user",
        "build", "make", "call", "step", "task", "verify", "fromjson", "string"
    ]

    private func extractKeyTerms(from texts: [String]) -> [String] {
        var freq: [String: Int] = [:]
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        for text in texts {
            tagger.string = text
            tagger.enumerateTags(
                in: text.startIndex..<text.endIndex,
                unit: .word,
                scheme: .lexicalClass
            ) { tag, range in
                guard let tag, tag == .noun else { return true }
                let word = String(text[range]).lowercased()
                guard word.count >= 4, word.count <= 18,
                      !word.contains(where: { $0.isNumber || $0.isPunctuation }),
                      !Self.ignoredTerms.contains(word) else { return true }
                freq[word, default: 0] += 1
                return true
            }
        }
        return freq.sorted { $0.value > $1.value }.prefix(4).map(\.key)
    }

    // MARK: - Helpers

    private func floatVector(from data: Data) -> [Float] {
        let size = MemoryLayout<Float>.size
        guard !data.isEmpty, data.count % size == 0 else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
