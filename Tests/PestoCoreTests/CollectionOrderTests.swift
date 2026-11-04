// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Order of clips in a collection")
struct CollectionOrderTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
        context = ModelContext(container)
    }

    private func clip(_ name: String, at seconds: Double, order: Int? = nil) -> ClipboardItem {
        let item = ClipboardItem(
            type: .text, previewText: name, contentHash: name, byteSize: name.utf8.count, deviceID: "t",
            sequenceNumber: Int64(seconds)
        )
        item.timestamp = Date(timeIntervalSince1970: seconds)
        context.insert(item)
        if let order { item.collectionOrder = order }
        return item
    }

    @Test("clips the person placed come first, in the order they were placed")
    func whenOrdered_thenByPosition() {
        let third = clip("c", at: 100, order: 2)
        let first = clip("a", at: 1, order: 0)
        let second = clip("b", at: 50, order: 1)
        #expect(CollectionOrder.sorted([third, first, second]).map(\.previewText) == ["a", "b", "c"])
    }

    @Test("clips never placed follow the placed ones, newest first")
    func whenUnordered_thenAfterOrderedNewestFirst() {
        let old = clip("old", at: 1)
        let placed = clip("placed", at: 2, order: 5)
        let new = clip("new", at: 9)
        #expect(CollectionOrder.sorted([old, new, placed]).map(\.previewText) == ["placed", "new", "old"])
    }

    @Test("two clips with the same position fall back to newest first")
    func whenSamePosition_thenNewestFirst() {
        let older = clip("older", at: 1, order: 3)
        let newer = clip("newer", at: 2, order: 3)
        #expect(CollectionOrder.sorted([older, newer]).map(\.previewText) == ["newer", "older"])
    }

    @Test("an empty list stays empty")
    func whenEmpty_thenEmpty() {
        #expect(CollectionOrder.sorted([]).isEmpty)
    }
}
