// SPDX-License-Identifier: MIT
import Foundation
import XCTest
@testable import PestoCore

final class SemanticIndexerTests: XCTestCase {
    // MARK: - Embedding input (the model's memory grows with the text: 50,000 characters peaked at 685 MB)

    func test_whenTextIsLong_thenEmbeddingInputIsCappedAtTheLimit() {
        let long = String(repeating: "basil ", count: 100_000)
        XCTAssertEqual(SemanticIndexer.embeddingInput(for: long).count, SemanticIndexer.maxEmbeddedCharacters)
        XCTAssertTrue(long.hasPrefix(SemanticIndexer.embeddingInput(for: long)))
    }

    func test_whenTextIsShort_thenEmbeddingInputIsUnchanged() {
        XCTAssertEqual(SemanticIndexer.embeddingInput(for: "quarterly numbers"), "quarterly numbers")
    }

    func test_whenTextEndsInsideAMultiScalarCharacter_thenItIsNotSplit() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let text = String(repeating: family, count: SemanticIndexer.maxEmbeddedCharacters + 5)
        let input = SemanticIndexer.embeddingInput(for: text)
        XCTAssertEqual(input.count, SemanticIndexer.maxEmbeddedCharacters)
        XCTAssertTrue(input.allSatisfy { String($0) == family })
    }

    // MARK: - Cosine similarity (pure math, no NLP model needed)

    func test_cosineSimilarity_identicalVectors_returnsOne() {
        let vec: [Float] = [1, 0, 0, 0]
        let data = floatData(vec)
        XCTAssertEqual(SemanticIndexer.cosineSimilarity(data, data), 1.0, accuracy: 0.001)
    }

    func test_cosineSimilarity_orthogonalVectors_returnsZero() {
        let a = floatData([1, 0, 0, 0])
        let b = floatData([0, 1, 0, 0])
        XCTAssertEqual(SemanticIndexer.cosineSimilarity(a, b), 0.0, accuracy: 0.001)
    }

    func test_cosineSimilarity_oppositeVectors_returnsNegativeOne() {
        let a = floatData([1, 0, 0, 0])
        let b = floatData([-1, 0, 0, 0])
        XCTAssertEqual(SemanticIndexer.cosineSimilarity(a, b), -1.0, accuracy: 0.001)
    }

    func test_cosineSimilarity_emptyData_returnsZero() {
        XCTAssertEqual(SemanticIndexer.cosineSimilarity(Data(), Data()), 0.0, accuracy: 0.001)
    }

    func test_cosineSimilarity_mismatchedSize_returnsZero() {
        let a = floatData([1, 0])
        let b = floatData([0, 1, 0])
        XCTAssertEqual(SemanticIndexer.cosineSimilarity(a, b), 0.0, accuracy: 0.001)
    }

    func test_cosineSimilarity_knownAngle() {
        // 45° between [1,1] and [1,0] → cos(45°) ≈ 0.707
        let a = floatData([1, 1])
        let b = floatData([1, 0])
        XCTAssertEqual(SemanticIndexer.cosineSimilarity(a, b), Float(1.0 / sqrt(2.0)), accuracy: 0.001)
    }

    // MARK: - Embed (may return nil when NLP model unavailable in test env)

    func test_embed_emptyString_returnsNil() async {
        let result = await SemanticIndexer.shared.embed(text: "")
        XCTAssertNil(result)
    }

    func test_embed_shortText_returnsNilOrData() async {
        // NLP model may not be downloaded in CI — nil is a valid response
        let result = await SemanticIndexer.shared.embed(text: "hello world")
        if let data = result {
            XCTAssertFalse(data.isEmpty)
            // Each float is 4 bytes; embedding should be at least 64-dimensional
            XCTAssertGreaterThanOrEqual(data.count, 64 * MemoryLayout<Float>.size)
        }
        // nil is acceptable when model unavailable
    }

    // MARK: - Helpers

    private func floatData(_ values: [Float]) -> Data {
        values.withUnsafeBytes { Data($0) }
    }
}
