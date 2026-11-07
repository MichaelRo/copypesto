// SPDX-License-Identifier: MIT
import AppKit
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

private struct ReadingRecognizer: TextRecognizing {
    let text: String?
    func recognize(imageData _: Data) async -> String? {
        text
    }
}

@Suite("Recognized text is kept whole, sealed, and only when it holds no secret", .serialized)
@MainActor
struct RecognizedTextIngestTests {
    private let container: ModelContainer
    private let directory: URL
    private let store: RecognizedTextStore

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-ocr-ingest-\(UUID().uuidString)", isDirectory: true)
        store = RecognizedTextStore(directory: directory)
    }

    private func service(
        reading text: String?, in container: ModelContainer? = nil, store: RecognizedTextStore? = nil
    )
    -> StorageService {
        StorageService(modelContainer: container ?? self.container, environment: .testing {
            $0.nsfwMode = { .show }
            $0.textRecognizer = ReadingRecognizer(text: text)
            $0.recognizedTexts = store ?? self.store
        })
    }

    private func picture() throws -> PasteboardCapture {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(
            red: .random(in: 0...1), green: .random(in: 0...1), blue: .random(in: 0...1), alpha: 1
        ).setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        return PasteboardCapture(typeIdentifier: "public.png", payload: png, contentHash: hash)
    }

    private func read(_ text: String?) async throws -> (service: StorageService, item: ClipboardItem) {
        let service = service(reading: text)
        try await service.ingest(picture())
        await service.waitForBackgroundWork()
        let item = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        return (service, item)
    }

    private func words(_ count: Int) -> String {
        (0..<count).map { "word\($0)" }.joined(separator: " ")
    }

    @Test("a long text is kept whole in a file while the preview keeps its first 500 characters")
    func whenTextIsLong_thenWholeTextKept() async throws {
        let long = words(400)
        let (_, item) = try await read(long)

        #expect(item.displayPreviewText == String(long.prefix(CardPreviewText.previewLength)))
        #expect(store.load(for: item.id) == long)
        #expect(RecognizedText.text(of: item, store: store) == long)
    }

    @Test("a short text keeps no file: the preview is the text")
    func whenTextIsShort_thenNoFile() async throws {
        let (_, item) = try await read("Boarding pass gate B22")

        #expect(!store.exists(for: item.id))
        #expect(RecognizedText.text(of: item, store: store) == "Boarding pass gate B22")
    }

    @Test("a text of exactly the preview length keeps a file, because it cannot be told from a cut one")
    func whenTextIsExactlyPreviewLength_thenFileKept() async throws {
        let text = String(repeating: "q", count: CardPreviewText.previewLength)
        let (_, item) = try await read(text)

        #expect(store.load(for: item.id) == text)
    }

    @Test("a text over the cap is kept up to the cap")
    func whenTextIsHuge_thenCapped() async throws {
        let (_, item) = try await read(String(repeating: "abcdefghi ", count: 20_000))

        let kept = try #require(store.load(for: item.id))
        #expect(kept.utf8.count == RecognizedText.maxBytes)
    }

    @Test("a key past the first 500 characters masks the picture and keeps no file")
    func whenSecretIsDeepInText_thenMaskedAndNoFile() async throws {
        let key = "sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef"
        let (_, item) = try await read(words(300) + " token \(key) for the server")

        #expect(item.sensitivityRaw != nil)
        #expect(!store.exists(for: item.id))
        #expect(RecognizedText.text(of: item, store: store) == nil)
        #expect(!RecognizedText.isOffered(for: item, store: store))
    }

    @Test("a key beyond 50 KB into a long text is found too")
    func whenSecretIsFarIntoText_thenMasked() async throws {
        let key = "sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef"
        let (_, item) = try await read(String(repeating: "lorem ipsum ", count: 6000) + " token \(key) for the server")

        #expect(item.sensitivityRaw != nil)
        #expect(!store.exists(for: item.id))
    }

    @Test("a picture with no text keeps nothing")
    func whenNoText_thenNothingKept() async throws {
        let (_, item) = try await read(nil)

        #expect(!store.exists(for: item.id))
        #expect(!RecognizedText.isOffered(for: item, store: store))
    }

    @Test("deleting the picture deletes its text; Undo brings it back")
    func whenDeletedAndUndone_thenTextFollows() async throws {
        let long = words(400)
        let (service, item) = try await read(long)
        let id = item.id

        _ = try await service.deleteItems(ids: [id], reason: .user)
        #expect(!store.exists(for: id))

        _ = try await service.undo()
        #expect(store.load(for: id) == long)
    }

    @Test("Clear Everything removes every recognized text")
    func whenEverythingCleared_thenNoFilesLeft() async throws {
        let (service, item) = try await read(words(400))
        #expect(store.exists(for: item.id))

        try await service.clearEverything()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("the text file holds no plaintext, and the database holds nothing past the preview")
    func whenKept_thenSealedOnDisk() async throws {
        let marker = "zebrafish quartz harbour lantern"
        let long = words(300) + " " + marker
        let (_, item) = try await read(long)
        #expect(store.load(for: item.id) == long)

        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first)
        #expect(try Data(contentsOf: file).range(of: Data(marker.utf8)) == nil)
        #expect(item.displayPreviewText.contains(marker) == false)
    }

    @Test("a backup made before this change restores with its full text, and a new backup carries no extra text")
    func whenRestored_thenFullTextRead() async throws {
        let long = words(400)
        let (source, item) = try await read(long)
        let export = try await source.backupRecords(includeSensitive: false)
        let record = try #require(export.records.first { $0.kind == .item })
        #expect(try JSONDecoder().decode(BackupItemMetadata.self, from: record.metadata).typeRaw == "image")
        #expect(!(String(bytes: record.metadata, encoding: .utf8) ?? "").contains("word399"))
        #expect(!record.payload.isEmpty)

        let targetContainer = try ModelContainerSetup.makeInMemory()
        let targetStore = RecognizedTextStore(directory: directory.appendingPathComponent("target"))
        let target = service(reading: long, in: targetContainer, store: targetStore)
        let manifest = BackupManifest(recordCount: 1, sequence: 1, deviceID: "t", createdAt: .now)
        let summary = try await target.restore(BackupContents(manifest: manifest, records: export.records))
        await target.waitForBackgroundWork()

        #expect(summary.restored == 1)
        let restored = try #require(try ModelContext(targetContainer).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(restored.id == item.id)
        #expect(targetStore.load(for: restored.id) == long)
    }

    private func textCapture(_ text: String) -> PasteboardCapture {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: data, payloadString: text, contentHash: hash
        )
    }

    private func clips(of type: ClipboardType) throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
            .filter { $0.type == type }
            .sorted { $0.timestamp > $1.timestamp }
    }

    @Test("copying the text of a picture makes its own text clip at the front, and the picture stays where it is")
    func whenTextIsCopied_thenItIsANewClipAtTheFront() async throws {
        let (service, picture) = try await read("Boarding pass gate B22")
        let pictureMovedAt = picture.timestamp

        try await service.ingest(textCapture("Boarding pass gate B22"))

        let texts = try clips(of: .text)
        #expect(texts.count == 1)
        #expect(texts.first?.displayPreviewText == "Boarding pass gate B22")
        #expect(try #require(texts.first).timestamp > pictureMovedAt)
        let pictureNow = try #require(try clips(of: .image).first)
        #expect(pictureNow.timestamp == pictureMovedAt)
    }

    @Test("copying text that is already a clip moves that clip to the front and stores no second one")
    func whenTheTextIsAlreadyAClip_thenThatClipMoves() async throws {
        let service = service(reading: "Boarding pass gate B22")
        try await service.ingest(textCapture("Boarding pass gate B22"))
        let original = try #require(try clips(of: .text).first)
        let firstStamp = original.timestamp
        try await service.ingest(picture())
        await service.waitForBackgroundWork()

        try await service.ingest(textCapture("Boarding pass gate B22"))

        let texts = try clips(of: .text)
        #expect(texts.count == 1)
        #expect(texts.first?.id == original.id)
        #expect(try #require(texts.first).timestamp > firstStamp)
        let order = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
            .sorted { $0.timestamp > $1.timestamp }
        #expect(order.first?.type == .text)
    }
}
