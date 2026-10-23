// SPDX-License-Identifier: MIT
import Foundation
import XCTest
@testable import PestoCore

final class SmartCollectionSuggestionsTests: XCTestCase {
    // MARK: - suggest

    func test_suggest_withFewItems_returnsEmpty() async {
        let items = (0..<3).map { _ in
            SmartCollectionSuggestions.ItemInput(id: UUID(), preview: "hello world", embedding: randomEmbedding())
        }
        let result = await SmartCollectionSuggestions.shared.suggest(items: items, k: 5)
        XCTAssertTrue(result.isEmpty)
    }

    func test_suggest_withSufficientItems_returnsNonEmpty() async {
        let items = (0..<20).map { i in
            SmartCollectionSuggestions.ItemInput(
                id: UUID(), preview: "item \(i) hello world code swift", embedding: randomEmbedding()
            )
        }
        let result = await SmartCollectionSuggestions.shared.suggest(items: items, k: 3)
        XCTAssertFalse(result.isEmpty)
    }

    func test_suggest_whenOneVectorHasAnotherLength_thenItIsLeftOutInsteadOfCrashing() async {
        var items = (0..<20).map { i in
            SmartCollectionSuggestions.ItemInput(
                id: UUID(), preview: "item \(i) hello world code swift", embedding: randomEmbedding()
            )
        }
        let stranger = UUID()
        items.append(.init(id: stranger, preview: "from another model", embedding: randomEmbedding(dim: 4)))
        items.append(.init(id: UUID(), preview: "no vector at all", embedding: Data()))

        let result = await SmartCollectionSuggestions.shared.suggest(items: items, k: 3)

        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.contains { $0.itemIDs.contains(stranger) }, "a vector of another length was clustered")
    }

    func test_suggest_noItemWithoutEmbedding_returnsEmpty() async {
        let result = await SmartCollectionSuggestions.shared.suggest(items: [], k: 5)
        XCTAssertTrue(result.isEmpty)
    }

    func test_suggest_eachSuggestionHasAtLeastTwoItems() async {
        let items = (0..<20).map { i in
            SmartCollectionSuggestions.ItemInput(
                id: UUID(), preview: "word example text \(i)", embedding: randomEmbedding()
            )
        }
        let result = await SmartCollectionSuggestions.shared.suggest(items: items, k: 5)
        for suggestion in result {
            XCTAssertGreaterThanOrEqual(suggestion.itemIDs.count, 2)
        }
    }

    func test_suggest_suggestionNamesAreNonEmpty() async {
        let items = (0..<15).map { i in
            SmartCollectionSuggestions.ItemInput(
                id: UUID(), preview: "document report meeting \(i)", embedding: randomEmbedding()
            )
        }
        let result = await SmartCollectionSuggestions.shared.suggest(items: items, k: 3)
        for suggestion in result {
            XCTAssertFalse(suggestion.name.isEmpty)
        }
    }

    // MARK: - Helpers

    private func randomEmbedding(dim: Int = 16) -> Data {
        var floats = (0..<dim).map { _ in Float.random(in: -1...1) }
        let mag = sqrt(floats.reduce(0) { $0 + $1 * $1 })
        if mag > 0 { floats = floats.map { $0 / mag } }
        return floats.withUnsafeBytes { Data($0) }
    }
}
