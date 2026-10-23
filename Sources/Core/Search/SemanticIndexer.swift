// SPDX-License-Identifier: MIT
import Foundation
import NaturalLanguage

/// On-device sentence embedding for semantic search.
///
/// Uses `NLEmbedding.sentenceEmbedding(for: .english)` which runs fully on-device — no network
/// calls, no data leaves the device. Vectors are 512-dimensional Float32 stored in `Data`.
///
/// The NLP model is downloaded by the OS on first use (automatic, ~15 MB). If the model is
/// unavailable (e.g. CI, offline), `embed(text:)` returns nil and callers degrade gracefully
/// to substring-only search.
public actor SemanticIndexer {
    public static let shared = SemanticIndexer()

    private var cachedEmbedding: NLEmbedding?

    /// `NLEmbedding.vector(for:)` allocates in proportion to the text. Measured: 2,000 characters peak at 61 MB,
    /// 50,000 at 685 MB, 200,000 at 2.6 GB over 6 s, and 1,000,000 aborts with `std::bad_alloc`. One long copy
    /// would stall the Mac, and a sentence vector needs only the start of the text.
    public static let maxEmbeddedCharacters = 2000

    public static func embeddingInput(for text: String) -> String {
        String(text.prefix(maxEmbeddedCharacters))
    }

    /// Returns a 512-element Float32 vector for `text`, or `nil` if the NLP model is unavailable.
    /// Short strings (≤ 8 chars) return nil — too little signal for sentence embedding.
    public func embed(text: String) -> Data? {
        let input = Self.embeddingInput(for: text)
        guard input.count > 8 else { return nil }
        if cachedEmbedding == nil {
            cachedEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        }
        guard let embedding = cachedEmbedding,
              let doubles = embedding.vector(for: input) else { return nil }
        let floats = doubles.map { Float($0) }
        return floats.withUnsafeBytes { Data($0) }
    }

    // MARK: - Cosine similarity

    /// Returns the cosine similarity between two Float32 vectors stored as Data.
    /// Returns 0 when either vector is empty or the sizes differ.
    public static func cosineSimilarity(_ a: Data, _ b: Data) -> Float {
        let strideSize = MemoryLayout<Float>.size
        guard !a.isEmpty, !b.isEmpty, a.count == b.count, a.count % strideSize == 0 else {
            return 0
        }
        let countA = a.count / strideSize
        return a.withUnsafeBytes { rawA in
            b.withUnsafeBytes { rawB in
                let vecA = rawA.bindMemory(to: Float.self)
                let vecB = rawB.bindMemory(to: Float.self)
                var dot: Float = 0
                var magA: Float = 0
                var magB: Float = 0
                for i in 0..<countA {
                    dot += vecA[i] * vecB[i]
                    magA += vecA[i] * vecA[i]
                    magB += vecB[i] * vecB[i]
                }
                let denom = sqrt(magA) * sqrt(magB)
                return denom > 0 ? dot / denom : 0
            }
        }
    }
}
