// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("KeyboardSize cycling and shared group store")
struct KeyboardSizeStoreTests {
    @Test("KeyboardSize cycles small -> medium -> large -> small with labels")
    func whenCycled_thenFollowsSmallMediumLargeOrder() {
        #expect(KeyboardSize.small.next == .medium)
        #expect(KeyboardSize.medium.next == .large)
        #expect(KeyboardSize.large.next == .small)

        #expect(KeyboardSize.small.shortLabel == "S")
        #expect(KeyboardSize.medium.shortLabel == "M")
        #expect(KeyboardSize.large.shortLabel == "L")

        #expect(KeyboardSize.small.displayName == "Small")
        #expect(KeyboardSize.medium.displayName == "Medium")
        #expect(KeyboardSize.large.displayName == "Large")
    }

    @Test("KeyboardSizeStore returns nil when missing or corrupt")
    func whenMissingOrCorrupt_thenLoadReturnsNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyboard-size-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = KeyboardSizeStore(root: dir)
        #expect(store.load() == nil)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url)
        #expect(store.load() == nil)
    }

    @Test("KeyboardSizeStore saves and loads records and overwrites older values")
    func whenSaved_thenLoadReturnsLatestRecord() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyboard-size-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = KeyboardSizeStore(root: dir)
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        try store.save(.large, at: firstDate)

        let first = try #require(store.load())
        #expect(first == KeyboardSizeStore.Record(size: .large, updatedAt: firstDate))

        let secondDate = Date(timeIntervalSince1970: 1_800_000_120)
        try store.save(.small, at: secondDate)

        let second = try #require(store.load())
        #expect(second == KeyboardSizeStore.Record(size: .small, updatedAt: secondDate))
    }
}
