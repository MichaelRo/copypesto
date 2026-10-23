// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("HistoryExporter privacy")
struct HistoryExporterPrivacyTests {
    private let cardNumber = "4242 4242 4242 4242"

    private func ingest(_ text: String, into container: ModelContainer) async throws {
        let service = StorageService(modelContainer: container)
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data(text.utf8),
            payloadString: text,
            contentHash: hash
        ))
    }

    private func encode(_ records: [HistoryExporter.HistoryRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records)
    }

    @Test("an export never contains the text of a sensitive item")
    func export_masksSensitiveItems() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        try await ingest(cardNumber, into: container)
        try await ingest("just a note", into: container)

        let data = try await HistoryExporter(modelContainer: container).export()
        let json = String(bytes: data, encoding: .utf8) ?? ""

        #expect(!json.contains(cardNumber))
        #expect(!json.contains("4242424242424242"))
        #expect(json.contains("just a note"))
    }

    @Test("importing a card number restores its sensitivity so it stays masked")
    func import_redetectsSensitivity() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let record = HistoryExporter.HistoryRecord(
            id: UUID(),
            timestamp: .now,
            type: "text",
            previewText: cardNumber,
            sourceApp: nil,
            sourceBundleID: nil,
            customTitle: nil,
            userNote: nil,
            tags: [],
            isPinned: false
        )
        let payload = try encode([record])

        try await HistoryExporter(modelContainer: destination).importRecords(from: payload)

        let items = try ModelContext(destination).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 1)
        #expect(items[0].sensitivityRaw == SensitivityCategory.creditCard.rawValue)
        #expect(items[0].gridPreview != cardNumber)
    }

    @Test("an imported text item gets the same content hash a live copy would, so it dedupes")
    func import_usesContentHash() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let text = "hello import"
        let record = HistoryExporter.HistoryRecord(
            id: UUID(), timestamp: .now, type: "text", previewText: text, sourceApp: nil, sourceBundleID: nil,
            customTitle: nil, userNote: nil, tags: [], isPinned: false
        )

        try await HistoryExporter(modelContainer: destination)
            .importRecords(from: encode([record]))

        let plain = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        let expected = ContentHash.stored(plain, key: try? BlobEncryption().loadOrCreateKey())
        let items = try ModelContext(destination).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.first?.contentHash == expected)
        #expect(items.first?.contentHash != plain, "the plain hash must not be stored")
    }

    @Test("an imported text clip keeps its text in an encrypted blob, so it pastes whole and is backed up")
    func import_givesATextClipABlob() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let text = "imported words \(UUID().uuidString)"
        let record = HistoryExporter.HistoryRecord(
            id: UUID(), timestamp: .now, type: "text", previewText: text, sourceApp: nil, sourceBundleID: nil,
            customTitle: nil, userNote: nil, tags: [], isPinned: false
        )

        try await HistoryExporter(modelContainer: destination).importRecords(from: encode([record]))

        let item = try #require(ModelContext(destination).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(item.blob?.decryptedText() == text)
        let export = try await StorageService(modelContainer: destination).backupRecords(includeSensitive: false)
        #expect(export.summary.items == 1)
    }

    private func clip(_ type: ClipboardType, preview: String, in context: ModelContext) {
        context.insert(ClipboardItem(
            type: type, previewText: preview, contentHash: UUID().uuidString, byteSize: preview.utf8.count,
            deviceID: "d", sequenceNumber: 1
        ))
    }

    @Test("an export holds text, code, links and colors only: no picture text and no file paths")
    func export_leavesOutPicturesAndFiles() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let context = ModelContext(container)
        clip(.text, preview: "a note", in: context)
        clip(.code, preview: "let x = 1", in: context)
        clip(.url, preview: "https://example.com", in: context)
        clip(.color, preview: "#336699", in: context)
        clip(.image, preview: "text read from a screenshot", in: context)
        clip(.file, preview: "/Users/someone/Documents/Tax 2025.pdf", in: context)
        try context.save()

        let json = try await String(bytes: HistoryExporter(modelContainer: container).export(), encoding: .utf8) ?? ""

        for kept in ["a note", "let x = 1", "example.com", "#336699"] {
            #expect(json.contains(kept), "\(kept)")
        }
        #expect(!json.contains("text read from a screenshot"))
        #expect(!json.contains("Tax 2025.pdf"))
    }

    @Test("importing skips picture and file records, which would become payload-less cards")
    func import_skipsPicturesAndFiles() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        func record(_ type: String, _ text: String) -> HistoryExporter.HistoryRecord {
            HistoryExporter.HistoryRecord(
                id: UUID(), timestamp: .now, type: type, previewText: text, sourceApp: nil, sourceBundleID: nil,
                customTitle: nil, userNote: nil, tags: [], isPinned: false
            )
        }

        let inserted = try await HistoryExporter(modelContainer: destination).importRecords(
            from: encode([record("text", "kept"), record("image", "ocr"), record("file", "/tmp/a.txt")])
        )

        #expect(inserted == 1)
        let items = try ModelContext(destination).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.map(\.typeRaw) == ["text"])
    }

    private func record(
        type: String = "text", preview: String, id: UUID = UUID()
    )
    -> HistoryExporter.HistoryRecord {
        HistoryExporter.HistoryRecord(
            id: id, timestamp: .now, type: type, previewText: preview, sourceApp: nil, sourceBundleID: nil,
            customTitle: nil, userNote: nil, tags: [], isPinned: false
        )
    }

    @Test("a record typed color that holds a sentence is sealed, not kept in the clear (R-02)")
    func import_colourRecordWithSentence_isSealed() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let sentence = "call the gas company about the invoice"
        let payload = try encode([record(type: "color", preview: sentence)])

        try await HistoryExporter(modelContainer: destination).importRecords(from: payload)

        let item = try #require(ModelContext(destination).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(item.type != .color)
        #expect(item.previewText.isEmpty, "the preview must be ciphertext")
        #expect(item.previewCiphertext != nil)
        #expect(item.displayPreviewText == sentence)
    }

    @Test("a record typed color that holds a card number is masked")
    func import_colourRecordWithCard_isMasked() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let payload = try encode([record(type: "color", preview: "\(cardNumber)")])

        try await HistoryExporter(modelContainer: destination).importRecords(from: payload)

        let item = try #require(ModelContext(destination).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(item.sensitivityRaw == SensitivityCategory.creditCard.rawValue)
        #expect(!item.previewText.contains("4242 4242 4242 4242"))
    }

    @Test("a real colour record is kept as a colour")
    func import_realColour_staysAColour() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let payload = try encode([record(type: "color", preview: "#FF5733")])

        try await HistoryExporter(modelContainer: destination).importRecords(from: payload)

        let item = try #require(ModelContext(destination).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(item.type == .color)
    }

    private struct SealFailure: Error {}

    @Test("when a preview cannot be sealed the record is skipped, never stored in plaintext")
    func import_sealFailure_importsNothingInPlaintext() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let exporter = HistoryExporter(modelContainer: destination)
        await exporter.useSealer { _, _ in throw SealFailure() }
        let payload = try encode([record(preview: "a note that must not land in the clear")])

        let imported = try await exporter.importRecords(from: payload)

        #expect(imported == 0)
        #expect(try ModelContext(destination).fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
    }

    @Test("a record longer than a preview can be is skipped")
    func import_oversizedRecord_isSkipped() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let huge = String(repeating: "x", count: HistoryExporter.maxRecordCharacters + 1)
        let payload = try encode([record(preview: huge), record(preview: "fine")])

        let imported = try await HistoryExporter(modelContainer: destination).importRecords(from: payload)

        #expect(imported == 1)
    }

    @Test("a file with more records than the cap imports nothing")
    func import_tooManyRecords_isRefused() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let records = (0...HistoryExporter.maxRecords).map { record(preview: "n\($0)") }
        let payload = try encode(records)

        await #expect(throws: HistoryExporter.ImportError.self) {
            try await HistoryExporter(modelContainer: destination).importRecords(from: payload)
        }
        #expect(try ModelContext(destination).fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
    }

    @Test("a file over the size cap is refused before it is read")
    func import_oversizedFile_isRefused() async throws {
        let destination = try ModelContainerSetup.makeInMemory().synced
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(HistoryExporter.maxImportBytes + 1))
        try handle.close()

        await #expect(throws: HistoryExporter.ImportError.self) {
            try await HistoryExporter(modelContainer: destination).importRecords(fromFile: file)
        }
    }
}
