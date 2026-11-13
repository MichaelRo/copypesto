// SPDX-License-Identifier: MIT
import AppKit
import Darwin
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PestoCore

@Suite("A collection file is untrusted input")
@MainActor
struct CollectionFileSafetyTests {
    private struct Side {
        let container: ModelContainer
        let storage: StorageService
        let exporter: HistoryExporter
    }

    private func side(_ configure: (inout StorageEnvironment) -> Void = { _ in }) throws -> Side {
        let container = try ModelContainerSetup.makeInMemory()
        return Side(
            container: container,
            storage: StorageService(modelContainer: container, environment: .testing(configure)),
            exporter: HistoryExporter(modelContainer: container)
        )
    }

    private func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    private func textItem(
        _ text: String,
        date: String = "2020-01-01T10:00:00Z",
        pinned: Bool = false
    )
    -> [String: Any] {
        [
            "id": UUID().uuidString, "timestamp": date, "type": "text", "previewText": text, "tags": [String](),
            "isPinned": pinned, "payloadType": "public.utf8-plain-text", "payload": base64(text)
        ]
    }

    private func fileJSON(board overrides: [String: Any] = [:], items: [[String: Any]]) throws -> Data {
        let board: [String: Any] = [
            "id": UUID().uuidString, "name": "Hand made", "symbolName": "star", "colorHex": "#3DAF60",
            "isSmart": false
        ].merging(overrides) { $1 }
        return try JSONSerialization.data(withJSONObject: ["version": 2, "collection": board, "items": items])
    }

    private func clips(_ side: Side) throws -> [ClipboardItem] {
        try ModelContext(side.container).fetch(FetchDescriptor<ClipboardItem>())
    }

    private func boards(_ side: Side) throws -> [Pinboard] {
        try ModelContext(side.container).fetch(FetchDescriptor<Pinboard>())
    }

    // MARK: Retention

    @Test(
        "imported clips enter the history now, so a retention sweep keeps them, and the file's date is the first copy"
    )
    func whenTheFileIsOld_thenRetentionKeepsTheClips() async throws {
        let data = try fileJSON(items: [
            textItem("old one", date: "2019-03-01T10:00:00Z"), textItem("older one", date: "2018-03-01T10:00:00Z")
        ])
        let destination = try side()

        try await destination.exporter.importCollection(from: data, storage: destination.storage)

        let imported = try clips(destination)
        let candidates = imported.map { ($0.id, $0.timestamp, $0.byteSize) }
        let evictions = RetentionPruner.computeEvictions(candidates: candidates, policy: .default, now: .now)
        #expect(imported.count == 2)
        #expect(evictions.isEmpty)
        #expect(imported.allSatisfy { abs($0.timestamp.timeIntervalSinceNow) < 60 })
        #expect(imported.map(\.copiedAt).allSatisfy { $0 < Date(timeIntervalSince1970: 1_600_000_000) })
    }

    @Test("a file with more than 1,000 clips is refused before anything is imported")
    func whenTheFileHasTooManyClips_thenItIsRefused() async throws {
        let items = (0...CollectionFilePolicy.maxClips).map { textItem("clip number \($0)") }
        let data = try fileJSON(items: items)
        let destination = try side()

        await #expect(throws: HistoryExporter.ImportError.tooManyRecords) {
            try await destination.exporter.importCollection(from: data, storage: destination.storage)
        }
        #expect(try clips(destination).isEmpty)
        #expect(throws: HistoryExporter.ImportError.tooManyRecords) { try CollectionFileType.summary(of: data) }
    }

    @Test("an export keeps the newest 1,000 clips and counts the rest")
    func whenTheCollectionIsHuge_thenExportKeepsTheNewestThousand() async throws {
        let source = try side()
        let boardID = UUID()
        let context = ModelContext(source.container)
        context.insert(Pinboard(id: boardID, name: "Big", symbolName: "star", colorHex: "3DAF60", sortOrder: 0))
        for index in 0...CollectionFilePolicy.maxClips {
            context.insert(ClipboardItem(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)), type: .color,
                previewText: "#00FF\(String(format: "%02X", index % 256))", contentHash: "hash-\(index)", byteSize: 7,
                deviceID: "test", sequenceNumber: Int64(index), collectionID: boardID
            ))
        }
        try context.save()

        let file = try await source.exporter.exportCollectionFile(id: boardID)

        #expect(file.exported == CollectionFilePolicy.maxClips)
        #expect(file.skippedOverLimit == 1)
    }

    @Test("the question before an import says how many of the oldest clips the limit would remove")
    func whenHistoryIsNearTheLimit_thenThePreviewSaysSo() async throws {
        let destination = try side()
        for index in 0..<8 {
            try await destination.storage.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data("own clip \(index)".utf8),
                payloadString: "own clip \(index)", contentHash: "own-\(index)"
            ))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("p-\(UUID().uuidString).pesto")
        defer { try? FileManager.default.removeItem(at: url) }
        try fileJSON(items: (0..<5).map { textItem("shared clip \($0)") } + [textItem("pinned", pinned: true)])
            .write(to: url)
        let policy = RetentionPolicy(maxAge: .infinity, maxItemCount: 10, maxTotalBytes: .max)

        let preview = try await destination.exporter.importPreview(fromFile: url, policy: policy)

        #expect(preview.importableCount == 6)
        #expect(preview.wouldRemove == 3)
        #expect(preview.limit == 10)
    }

    // MARK: Partial failure

    @Test("one clip that cannot be stored is counted, and the others still land in the collection")
    func whenOneIngestFails_thenTheRestAreImportedAndFiled() async throws {
        let calls = Mutex(0)
        let destination = try side { environment in
            environment.previewSealer = { data, associatedData in
                let call = calls.withLock { count -> Int in
                    count += 1
                    return count
                }
                if call == 2 { throw CocoaError(.fileWriteUnknown) }
                return try BlobEncryption().encrypt(data, associatedData: associatedData)
            }
        }
        let data = try fileJSON(items: [
            textItem("first words", date: "2020-01-01T10:00:00Z"),
            textItem("second words", date: "2020-01-02T10:00:00Z"),
            textItem("third words", date: "2020-01-03T10:00:00Z")
        ])
        let history = UndoHistory()

        let result = try await destination.exporter.importCollection(
            from: data, storage: destination.storage, undoHistory: history
        )

        #expect(result.itemsImported == 2)
        #expect(result.skippedUnreadable == 1)
        let board = try #require(boards(destination).first)
        #expect(try clips(destination).count == 2)
        #expect(try clips(destination).allSatisfy { $0.collectionID == board.id })
        #expect(history.undoLabel == .importCollection("Hand made"))
    }

    // MARK: Reading the file

    @Test("a named pipe, a folder and a link to a folder are refused without being read")
    func whenTheFileIsNotRegular_thenItIsRefused() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("odd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pipe = folder.appendingPathComponent("pipe.pesto")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        let directory = folder.appendingPathComponent("dir.pesto")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("link.pesto")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        let destination = try side()

        for url in [pipe, directory, link] {
            await #expect(throws: HistoryExporter.ImportError.notARegularFile) {
                try await destination.exporter.importCollection(fromFile: url, storage: destination.storage)
            }
        }
    }

    @Test("a link to a regular file is followed")
    func whenTheFileIsALinkToAFile_thenItIsRead() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = folder.appendingPathComponent("real.json")
        try fileJSON(items: [textItem("through a link")]).write(to: real)
        let link = folder.appendingPathComponent("link.pesto")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let destination = try side()

        let result = try await destination.exporter.importCollection(fromFile: link, storage: destination.storage)

        #expect(result.itemsImported == 1)
    }

    // MARK: The collection's own fields

    @Test("a name loses control and bidi characters and is cut to 100 characters")
    func whenTheNameIsHostile_thenItIsCleaned() async throws {
        let hostile = "\u{202E}Hello\u{0007}\u{200B} " + String(repeating: "x", count: 300)
        let destination = try side()

        let result = try await destination.exporter.importCollection(
            from: fileJSON(board: ["name": hostile], items: [textItem("a clip")]), storage: destination.storage
        )

        let name = try #require(boards(destination).first?.name)
        #expect(name.count <= CollectionFilePolicy.maxNameLength)
        #expect(name.hasPrefix("Hello"))
        #expect(!name.unicodeScalars.contains { $0.properties.generalCategory == .control })
        #expect(!name.unicodeScalars.contains { $0.properties.generalCategory == .format })
        #expect(result.collectionName == name)
    }

    @Test("a collection is matched by name only, and a new one never takes the file's id")
    func whenTheIDMatches_thenItIsStillANewCollection() async throws {
        let destination = try side()
        let existingID = UUID()
        let context = ModelContext(destination.container)
        context.insert(Pinboard(id: existingID, name: "Mine", symbolName: "star", colorHex: "007AFF", sortOrder: 0))
        try context.save()

        let result = try await destination.exporter.importCollection(
            from: fileJSON(board: ["id": existingID.uuidString, "name": "Theirs"], items: [textItem("a clip")]),
            storage: destination.storage
        )

        #expect(result.collectionID != existingID)
        #expect(try boards(destination).count == 2)
        #expect(try clips(destination).first?.collectionID == result.collectionID)

        let again = try await destination.exporter.importCollection(
            from: fileJSON(board: ["name": "Mine"], items: [textItem("another clip")]), storage: destination.storage
        )
        #expect(again.collectionID == existingID)
    }

    @Test("an unknown icon, a bad color and a smart rule are replaced by plain defaults")
    func whenTheFieldsAreInvalid_thenTheCollectionIsPlain() async throws {
        let destination = try side()

        try await destination.exporter.importCollection(
            from: fileJSON(
                board: [
                    "symbolName": "../../etc/passwd", "colorHex": "javascript:alert(1)", "isSmart": true,
                    "smartPredicateData": Data("{\"rules\":[]}".utf8).base64EncodedString()
                ],
                items: [textItem("a clip")]
            ),
            storage: destination.storage
        )

        let board = try #require(boards(destination).first)
        #expect(board.symbolName == CollectionFilePolicy.defaultSymbol)
        #expect(CollectionPalette.colors.contains(board.colorHex))
        #expect(!board.isSmart)
        #expect(board.smartPredicateData == nil)
    }

    // MARK: Ids and clips already here

    @Test("clips get new ids, and a tombstone for the file's id does not stop one")
    func whenTheIDIsTombstoned_thenTheClipIsStillImported() async throws {
        let destination = try side()
        let record = textItem("once deleted")
        let recordID = try #require(UUID(uuidString: record["id"] as? String ?? ""))
        let context = ModelContext(destination.container)
        context.insert(DeletedItemTombstone(id: recordID))
        try context.save()

        let result = try await destination.exporter.importCollection(
            from: fileJSON(items: [record]), storage: destination.storage
        )

        #expect(result.itemsImported == 1)
        #expect(try clips(destination).first?.id != recordID)
    }

    @Test("a clip the history holds outside any collection is put into the collection; one in another is left")
    func whenAClipIsAlreadyHere_thenItJoinsTheCollectionIfItHasNone() async throws {
        let destination = try side()
        for text in ["loose clip", "filed clip"] {
            try await destination.storage.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                contentHash: Data(text.utf8).sha256Hex
            ))
        }
        let elsewhere = UUID()
        let context = ModelContext(destination.container)
        context.insert(Pinboard(id: elsewhere, name: "Elsewhere", symbolName: "star", colorHex: "007AFF", sortOrder: 0))
        try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first { $0.displayPreviewText == "filed clip" })
            .collectionID = elsewhere
        try context.save()

        let result = try await destination.exporter.importCollection(
            from: fileJSON(items: [textItem("loose clip"), textItem("filed clip"), textItem("brand new")]),
            storage: destination.storage
        )

        #expect(result.itemsImported == 1)
        #expect(result.alreadyPresent == 2)
        #expect(result.addedToCollection == 1)
        let byText = try Dictionary(uniqueKeysWithValues: clips(destination).map { ($0.displayPreviewText, $0) })
        #expect(byText["loose clip"]?.collectionID == result.collectionID)
        #expect(byText["filed clip"]?.collectionID == elsewhere)
        #expect(byText["brand new"]?.collectionID == result.collectionID)
    }

    @Test("a version 1 file imported twice adds its clips once")
    func whenAVersionOneFileIsImportedTwice_thenItIsAddedOnce() async throws {
        let record: [String: Any] = [
            "id": UUID().uuidString, "timestamp": "2020-01-01T10:00:00Z", "type": "text",
            "previewText": "old style", "tags": [String](), "isPinned": false
        ]
        let data = try fileJSON(items: [record])
        let destination = try side()

        try await destination.exporter.importCollection(from: data, storage: destination.storage)
        let again = try await destination.exporter.importCollection(from: data, storage: destination.storage)

        #expect(again.itemsImported == 0)
        #expect(again.alreadyPresent == 1)
        #expect(try clips(destination).count == 1)
    }

    // MARK: PDF and SVG

    @Test("a PDF that opens is imported, a broken one is not, and SVG is not importable")
    func whenPDFAndSVGArrive_thenOnlyAReadablePDFIsImported() async throws {
        let pdfData = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: pdfData as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        func picture(_ type: String, _ bytes: Data) -> [String: Any] {
            [
                "id": UUID().uuidString, "timestamp": "2020-01-01T10:00:00Z", "type": "image", "previewText": "",
                "tags": [String](), "isPinned": false, "payloadType": type, "payload": bytes.base64EncodedString()
            ]
        }
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"https://example.com/x.png\"/></svg>"
            .utf8)
        let data = try fileJSON(items: [
            picture("com.adobe.pdf", pdfData as Data), picture("com.adobe.pdf", Data("%PDF- broken".utf8)),
            picture("public.svg-image", svg)
        ])
        let destination = try side()

        let result = try await destination.exporter.importCollection(from: data, storage: destination.storage)

        #expect(result.itemsImported == 1)
        #expect(result.skippedUnreadable == 2)
    }
}
