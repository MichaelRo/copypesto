// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("LastItemStore", .serialized)
struct LastItemStoreTests {
    private static let testURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("pesto-test-last-item-\(UUID().uuidString).json")

    init() {
        LastItemStore.testFileURL = Self.testURL
        try? FileManager.default.removeItem(at: Self.testURL)
    }

    @Test
    func write_roundTrip_restoresAllFields() throws {
        let preview = "Hello, clipboard"
        let timestamp = Date(timeIntervalSinceReferenceDate: 123_456_789)

        LastItemStore.write(preview: preview, type: "text", timestamp: timestamp, sourceApp: "TextEdit")
        let item = try #require(LastItemStore.read())

        #expect(item.preview == preview)
        #expect(item.type == "text")
        #expect(item.sourceApp == "TextEdit")
        // ISO-8601 round-trip is accurate to the millisecond; 1-second tolerance is generous.
        #expect(abs(item.timestamp.timeIntervalSince(timestamp)) < 1)
    }

    @Test
    func write_withNilSourceApp_roundTrips() throws {
        LastItemStore.write(preview: "x", type: "url", timestamp: .now, sourceApp: nil)
        let item = try #require(LastItemStore.read())
        #expect(item.sourceApp == nil)
    }

    @Test
    func read_whenFileAbsent_returnsNil() {
        #expect(LastItemStore.read() == nil)
    }

    @Test
    func write_isAtomic_secondWriteOverwritesFirst() throws {
        LastItemStore.write(preview: "first", type: "text", timestamp: .now, sourceApp: nil)
        LastItemStore.write(preview: "second", type: "text", timestamp: .now, sourceApp: nil)
        let item = try #require(LastItemStore.read())
        #expect(item.preview == "second")
    }

    @Test
    func write_leavesTheFileOwnerOnly() throws {
        LastItemStore.write(preview: "x", type: "text", timestamp: .now, sourceApp: nil)
        LastItemStore.write(preview: "y", type: "text", timestamp: .now, sourceApp: nil)

        let attributes = try FileManager.default.attributesOfItem(atPath: Self.testURL.path)
        #expect((attributes[.posixPermissions] as? Int).map { $0 & 0o777 } == 0o600)
    }

    // MARK: - Removal (the file kept the last clip's text after it was deleted or cleared)

    @Test
    func clear_removesTheFile() {
        LastItemStore.write(preview: "secret", type: "text", timestamp: .now, sourceApp: nil)

        LastItemStore.clear()

        #expect(LastItemStore.read() == nil)
    }

    @Test
    func clearIfItemID_removesOnlyWhenTheStoredItemMatches() {
        let id = UUID()
        LastItemStore.write(id: id, preview: "secret", type: "text", timestamp: .now, sourceApp: nil)

        LastItemStore.clear(ifItemID: UUID())
        #expect(LastItemStore.read()?.preview == "secret", "a different item's deletion must not clear it")

        LastItemStore.clear(ifItemID: id)
        #expect(LastItemStore.read() == nil)
    }

    @Test
    func read_restoresTheItemID() {
        let id = UUID()
        LastItemStore.write(id: id, preview: "x", type: "text", timestamp: .now, sourceApp: nil)
        #expect(LastItemStore.read()?.id == id)
    }

    @Test
    func read_acceptsAFileWrittenBeforeIDsExisted() throws {
        let legacy = #"{"preview":"old","type":"text","timestamp":"2026-01-01T00:00:00Z"}"#
        try Data(legacy.utf8).write(to: Self.testURL)

        let item = try #require(LastItemStore.read())

        #expect(item.preview == "old")
        #expect(item.id == nil)
    }

    @Test("switching the lock on removes the plaintext last-item file")
    func whenLockSwitchedOn_thenFileRemoved() {
        LastItemStore.write(preview: "hello", type: "text", timestamp: .now, sourceApp: nil)
        #expect(LastItemStore.read() != nil)

        HistoryLockPolicy.lockWasSwitchedOn()

        #expect(LastItemStore.read() == nil)
    }

    @Test("the command line reads nothing while the lock is on")
    func whenLockIsOn_thenCommandLineGetsNothing() {
        LastItemStore.write(preview: "hello", type: "text", timestamp: .now, sourceApp: nil)

        #expect(LastItemStore.read(lockIsOn: true) == nil)
        #expect(LastItemStore.read(lockIsOn: false)?.preview == "hello")
    }
}
