// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

/// Export/import round-trips, the encrypted blob round-trip via `@Attribute(.externalStorage)`, and deletion not
/// resurrecting after re-import.
///
/// Lives in PestoTests (xcodebuild target) rather than PestoCoreTests because
/// SwiftData models cannot be built by the SPM target (see Pesto.yml comment
/// on `Sources/Core/Storage/Models`).
@Suite("Sync round-trip")
struct SyncRoundTripTests {
    // MARK: - Helpers

    private static func makeItem(
        id: UUID = UUID(),
        deviceID: String,
        seq: Int64,
        timestamp: Date,
        contentHash: String? = nil,
        previewText: String = "hello"
    )
    -> ClipboardItem {
        ClipboardItem(
            id: id,
            timestamp: timestamp,
            type: .text,
            previewText: previewText,
            contentHash: contentHash ?? UUID().uuidString,
            byteSize: previewText.utf8.count,
            deviceID: deviceID,
            sequenceNumber: seq
        )
    }

    // MARK: - HistoryExporter round-trip

    @Test("export then import on a fresh store re-creates every record")
    func exportImport_roundtrip_preservesItems() async throws {
        let source = try ModelContainerSetup.makeInMemory()
        let sourceCtx = ModelContext(source)
        for i in 0..<5 {
            sourceCtx.insert(Self.makeItem(
                deviceID: "device-A",
                seq: Int64(i),
                timestamp: Date().addingTimeInterval(Double(i)),
                previewText: "item-\(i)"
            ))
        }
        try sourceCtx.save()

        let exporter = HistoryExporter(modelContainer: source)
        let payload = try await exporter.export()

        let destination = try ModelContainerSetup.makeInMemory()
        let destImporter = HistoryExporter(modelContainer: destination)
        let inserted = try await destImporter.importRecords(from: payload)
        #expect(inserted == 5)

        let destCtx = ModelContext(destination)
        let items = try destCtx.fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 5)
        // Text previews are stored encrypted (ADR 0002), so the readable value is displayPreviewText.
        #expect(Set(items.map(\.displayPreviewText)) == Set((0..<5).map { "item-\($0)" }))
    }

    @Test("re-importing the same payload is idempotent — second import inserts 0 records")
    func exportImport_idempotent() async throws {
        let source = try ModelContainerSetup.makeInMemory()
        let sourceCtx = ModelContext(source)
        sourceCtx.insert(Self.makeItem(deviceID: "A", seq: 1, timestamp: .now))
        try sourceCtx.save()

        let payload = try await HistoryExporter(modelContainer: source).export()
        let dest = try ModelContainerSetup.makeInMemory()
        let destImporter = HistoryExporter(modelContainer: dest)

        let first = try await destImporter.importRecords(from: payload)
        let second = try await destImporter.importRecords(from: payload)
        #expect(first == 1)
        #expect(second == 0)
    }

    // MARK: - Blob external-storage round-trip

    @Test("encrypted blob attached via @Attribute(.externalStorage) round-trips through SwiftData")
    func blob_roundTrip_throughSwiftData() throws {
        let container = try ModelContainerSetup.makeInMemory()
        let ctx = ModelContext(container)

        // Use the test-friendly encryption variant so the test never touches the Keychain.
        let crypto = BlobEncryptionWithKey(key: SymmetricKey(size: .bits256))
        let plaintext = Data("the rain in spain falls mainly on the plain".utf8)
        let envelope = try crypto.encrypt(plaintext)
        let blob = ClipboardBlob(
            encryptedData: envelope.ciphertext,
            nonceData: envelope.nonce,
            mimeType: "public.utf8-plain-text"
        )
        let item = Self.makeItem(deviceID: "A", seq: 1, timestamp: .now, previewText: "preview")
        item.blob = blob
        ctx.insert(item)
        try ctx.save()

        // Fresh context — forces SwiftData to materialize from the store rather than
        // serve a cached object graph.
        let fresh = ModelContext(container)
        let fetched = try fresh.fetch(FetchDescriptor<ClipboardItem>())
        #expect(fetched.count == 1)
        let storedBlob = try #require(fetched[0].blob)
        // Security invariant: bytes at rest must not equal plaintext.
        #expect(storedBlob.encryptedData != plaintext)

        let decrypted = try crypto.decrypt(
            BlobEncryption.EncryptedEnvelope(
                ciphertext: storedBlob.encryptedData,
                nonce: storedBlob.nonceData
            )
        )
        #expect(decrypted == plaintext)
    }

    // MARK: - Deletion does not resurrect

    @Test("deleting an item then re-importing does not resurrect it (tombstone prevents re-import)")
    func deletion_doesNotResurrectAfterImport() async throws {
        let source = try ModelContainerSetup.makeInMemory()
        let sourceCtx = ModelContext(source)
        sourceCtx.insert(Self.makeItem(
            deviceID: "A",
            seq: 1,
            timestamp: .now,
            contentHash: "h-doomed",
            previewText: "doomed"
        ))
        try sourceCtx.save()

        let dest = try ModelContainerSetup.makeInMemory()
        let destImporter = HistoryExporter(modelContainer: dest)
        let payload = try await HistoryExporter(modelContainer: source).export()
        _ = try await destImporter.importRecords(from: payload)

        // Deleting must go through StorageService: only it records the tombstone that blocks re-import.
        let service = StorageService(modelContainer: dest)
        let ids = try ModelContext(dest).fetch(FetchDescriptor<ClipboardItem>()).map(\.id)
        for id in ids {
            #expect(try await service.deleteItem(id: id))
        }
        #expect(try ModelContext(dest).fetch(FetchDescriptor<DeletedItemTombstone>()).count == ids.count)

        let resurrected = try await destImporter.importRecords(from: payload)
        #expect(resurrected == 0)
    }
}
