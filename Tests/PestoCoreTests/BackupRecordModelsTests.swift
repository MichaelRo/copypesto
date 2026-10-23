// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Backup record models")
struct BackupRecordModelsTests {
    private let when = Date(timeIntervalSince1970: 1_800_000_000.123456)

    private func item() -> BackupItemMetadata {
        BackupItemMetadata(
            id: UUID(), timestamp: when, typeRaw: "text", mimeType: "public.utf8-plain-text", plainHash: "abc",
            sourceBundleID: "com.apple.Notes", sourceAppName: "Notes", customTitle: "Deploy", userNote: "check twice",
            tags: ["ops", "weekly"], isPinned: true, collectionID: UUID(), pinnedHotkeyIndex: 3,
            expiresAt: when.addingTimeInterval(3600), isNSFW: false, pasteCount: 4
        )
    }

    @Test("an item record carries its metadata and payload and reads back the same")
    func whenItemEncoded_thenRoundTrips() throws {
        let metadata = item()

        let record = try BackupRecord.item(metadata, payload: Data("hello".utf8))

        #expect(record.kind == .item)
        #expect(record.payload == Data("hello".utf8))
        #expect(try record.itemMetadata() == metadata)
    }

    @Test("a collection record keeps a smart collection's predicate bytes")
    func whenCollectionEncoded_thenRoundTrips() throws {
        let metadata = BackupCollectionMetadata(
            id: UUID(), name: "Pesto night", symbolName: "fork.knife", colorHex: "#2F7A49", sortOrder: 2,
            isSmart: true, smartPredicateData: Data([1, 2, 3]), schemaVersion: 1, triggerBundleID: nil
        )

        let record = try BackupRecord.collection(metadata)

        #expect(record.kind == .collection)
        #expect(try record.collectionMetadata() == metadata)
    }

    @Test("a tombstone record says which clip was deleted on purpose, and when")
    func whenTombstoneEncoded_thenRoundTrips() throws {
        let metadata = BackupTombstoneMetadata(id: UUID(), deletedAt: when)

        let record = try BackupRecord.tombstone(metadata)

        #expect(record.kind == .tombstone)
        #expect(record.payload.isEmpty)
        #expect(try record.tombstoneMetadata() == metadata)
    }

    @Test("reading a record as the wrong kind, or garbage, throws instead of guessing")
    func whenWrongKind_thenThrows() throws {
        let record = try BackupRecord.tombstone(BackupTombstoneMetadata(id: UUID(), deletedAt: when))

        #expect(throws: BackupError.corrupted) { _ = try record.itemMetadata() }
        #expect(throws: BackupError.corrupted) {
            _ = try BackupRecord(kind: .item, metadata: Data("not json".utf8)).itemMetadata()
        }
    }

    @Test("a record written by a newer Pesto with extra fields still reads")
    func whenUnknownFieldsPresent_thenIgnored() throws {
        let metadata = BackupTombstoneMetadata(id: UUID(), deletedAt: when)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder.backupRecords.encode(metadata)) as? [String: Any]
        )
        object["futureField"] = "later"
        let record = try BackupRecord(kind: .tombstone, metadata: JSONSerialization.data(withJSONObject: object))

        #expect(try record.tombstoneMetadata() == metadata)
    }
}
