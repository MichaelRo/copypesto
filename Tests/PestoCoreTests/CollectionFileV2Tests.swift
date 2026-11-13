// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Collection files carry pictures and files")
@MainActor
struct CollectionFileV2Tests {
    private let boardID = UUID()

    private func pngData(red: CGFloat = 0.2) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedRed: red, green: 0.6, blue: 0.4, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 24, height: 16)).fill()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 3, y: 3, width: 9, height: 5)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private func capture(
        _ type: String, _ payload: Data, text: String? = nil, concealed: Bool = false
    )
    -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: type, payload: payload, payloadString: text,
            contentHash: payload.sha256Hex, isConcealed: concealed
        )
    }

    private func textCapture(_ text: String, concealed: Bool = false) -> PasteboardCapture {
        capture("public.utf8-plain-text", Data(text.utf8), text: text, concealed: concealed)
    }

    private struct Side {
        let container: ModelContainer
        let storage: StorageService
        let exporter: HistoryExporter
    }

    private func side() throws -> Side {
        let container = try ModelContainerSetup.makeInMemory()
        return Side(
            container: container,
            storage: StorageService(modelContainer: container, environment: .testing()),
            exporter: HistoryExporter(modelContainer: container)
        )
    }

    private func source(_ captures: [PasteboardCapture]) async throws -> Side {
        let side = try side()
        for capture in captures {
            try await side.storage.ingest(capture)
        }
        await side.storage.waitForBackgroundWork()
        let context = ModelContext(side.container)
        context.insert(Pinboard(id: boardID, name: "Mixed", symbolName: "star", colorHex: "#3DAF60", sortOrder: 0))
        try context.fetch(FetchDescriptor<ClipboardItem>()).forEach { $0.collectionID = boardID }
        try context.save()
        return side
    }

    private func clips(_ side: Side) throws -> [ClipboardItem] {
        try ModelContext(side.container).fetch(FetchDescriptor<ClipboardItem>())
    }

    private func fileJSON(version: Int = 2, items: [[String: Any]]) throws -> Data {
        let board: [String: Any] = [
            "id": boardID.uuidString, "name": "Hand made", "symbolName": "star", "colorHex": "#3DAF60",
            "isSmart": false
        ]
        let object: [String: Any] = ["version": version, "collection": board, "items": items]
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func item(
        type: String = "image", payloadType: String?, payload: String?, preview: String = ""
    )
    -> [String: Any] {
        var record: [String: Any] = [
            "id": UUID().uuidString, "timestamp": "2026-11-01T10:00:00Z", "type": type, "previewText": preview,
            "tags": [String](), "isPinned": false, "somethingNew": "ignored"
        ]
        if let payloadType { record["payloadType"] = payloadType }
        if let payload { record["payload"] = payload }
        return record
    }

    // MARK: Round trip

    @Test("a text and a picture come back with their bytes, a long text whole, and a file clip is left out")
    func whenExported_thenTextAndPictureRoundTripAndFileIsLeftOut() async throws {
        let png = try pngData()
        let longText = String(repeating: "A long paragraph that the old preview cut at 500 characters. ", count: 40)
        let fileURL = "file:///Users/someone/Documents/report.pdf"
        let source = try await source([
            textCapture(longText),
            capture("public.png", png),
            capture("public.file-url", Data(fileURL.utf8), text: fileURL)
        ])

        let file = try await source.exporter.exportCollectionFile(id: boardID)
        #expect(file.exported == 2)
        #expect(file.skippedFiles == 1)
        #expect(!(String(bytes: file.data, encoding: .utf8) ?? "").contains(Data(fileURL.utf8).base64EncodedString()))

        let destination = try side()
        let result = try await destination.exporter.importCollection(from: file.data, storage: destination.storage)
        await destination.storage.waitForBackgroundWork()

        #expect(result.itemsImported == 2)
        #expect(result.collectionID == boardID)
        let imported = try clips(destination)
        #expect(Set(imported.map(\.typeRaw)) == ["text", "image"])
        #expect(imported.allSatisfy { $0.collectionID == boardID })
        let text = try #require(imported.first { $0.type == .text })
        #expect(text.blob?.decryptedText() == longText)
        let picture = try #require(imported.first { $0.type == .image })
        #expect(picture.blob?.decryptedData() == png)
        #expect(picture.blob?.mimeType == "public.png")
    }

    @Test("title, note, tags and pin travel with a picture")
    func whenAPictureHasNotes_thenTheyArriveToo() async throws {
        let source = try await source([capture("public.png", pngData())])
        let context = ModelContext(source.container)
        let original = try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first)
        original.customTitle = "Logo"
        original.userNote = "final one"
        original.tags = ["brand"]
        original.isPinned = true
        try context.save()

        let file = try await source.exporter.exportCollectionFile(id: boardID)
        let destination = try side()
        try await destination.exporter.importCollection(from: file.data, storage: destination.storage)

        let imported = try #require(clips(destination).first)
        #expect(imported.customTitle == "Logo")
        #expect(imported.userNote == "final one")
        #expect(imported.tags == ["brand"])
        #expect(imported.isPinned)
    }

    @Test("importing the same file again adds nothing and says so")
    func whenImportedTwice_thenEverythingIsAlreadyPresent() async throws {
        let source = try await source([capture("public.png", pngData()), textCapture("hi there")])
        let file = try await source.exporter.exportCollectionFile(id: boardID)
        let destination = try side()
        try await destination.exporter.importCollection(from: file.data, storage: destination.storage)

        let again = try await destination.exporter.importCollection(from: file.data, storage: destination.storage)

        #expect(again.itemsImported == 0)
        #expect(again.alreadyPresent == 2)
        #expect(try clips(destination).count == 2)
    }

    @Test("a picture that is already in the history under another id is not added twice")
    func whenTheBytesAreAlreadyThere_thenItIsAlreadyPresent() async throws {
        let png = try pngData()
        let source = try await source([capture("public.png", png)])
        let file = try await source.exporter.exportCollectionFile(id: boardID)
        let destination = try side()
        try await destination.storage.ingest(capture("public.png", png))
        await destination.storage.waitForBackgroundWork()

        let result = try await destination.exporter.importCollection(from: file.data, storage: destination.storage)

        #expect(result.alreadyPresent == 1)
        #expect(try clips(destination).count == 1)
    }

    // MARK: Older files

    @Test("a version 1 file with only previews still imports as text")
    func whenVersionOne_thenItImports() async throws {
        let data = try fileJSON(
            version: 1, items: [item(type: "text", payloadType: nil, payload: nil, preview: "old clip")]
        )
        let destination = try side()

        let result = try await destination.exporter.importCollection(from: data, storage: destination.storage)

        #expect(result.itemsImported == 1)
        #expect(try clips(destination).first?.displayPreviewText == "old clip")
    }

    @Test("a file from a newer version than this one is refused")
    func whenNewerVersion_thenRefused() async throws {
        let data = try fileJSON(version: 3, items: [])
        let destination = try side()
        await #expect(throws: HistoryExporter.ImportError.unsupportedVersion) {
            try await destination.exporter.importCollection(from: data, storage: destination.storage)
        }
    }

    // MARK: Limits

    @Test("a clip over the payload cap is left out of the file and counted")
    func whenAClipIsTooBig_thenExportSkipsIt() async throws {
        let big = Data(count: CollectionFilePolicy.maxPayloadBytes + 1)
        let source = try await source([capture("public.png", big), textCapture("ok then")])

        let file = try await source.exporter.exportCollectionFile(id: boardID)

        #expect(file.exported == 1)
        #expect(file.skippedTooLarge == 1)
        #expect(file.data.count < 10_000)
    }

    @Test("a payload over the cap in a file is skipped before it is decoded, and the others still import")
    func whenAPayloadIsTooBig_thenImportSkipsItAndCounts() async throws {
        let big = Data(count: CollectionFilePolicy.maxPayloadBytes + 1).base64EncodedString()
        let ok = try pngData().base64EncodedString()
        let data = try fileJSON(items: [
            item(payloadType: "public.png", payload: big),
            item(payloadType: "public.png", payload: ok)
        ])
        let destination = try side()

        let result = try await destination.exporter.importCollection(from: data, storage: destination.storage)

        #expect(result.itemsImported == 1)
        #expect(result.skippedTooLarge == 1)
    }

    @Test("a file over 64 MB is refused before any of it is read")
    func whenTheFileIsHuge_thenItIsRefusedUnread() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("huge-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(HistoryExporter.maxImportBytes + 1))
        try handle.close()
        let destination = try side()

        await #expect(throws: HistoryExporter.ImportError.fileTooLarge) {
            try await destination.exporter.importCollection(fromFile: url, storage: destination.storage)
        }
        #expect(try clips(destination).isEmpty)
    }

    // MARK: What is never written

    @Test("a secret and a hidden clip are not in the file, not even masked, and are counted")
    func whenSensitive_thenNeverWritten() async throws {
        let source = try await source([
            textCapture("4111 1111 1111 1111"),
            textCapture("hunter2-password", concealed: true),
            textCapture("plain note")
        ])
        let masks = try clips(source).compactMap(\.sensitivityMaskedPreview)
        #expect(masks.count == 2)

        let file = try await source.exporter.exportCollectionFile(id: boardID)
        let text = try #require(String(bytes: file.data, encoding: .utf8))

        #expect(file.exported == 1)
        #expect(file.skippedSensitive == 2)
        #expect(!text.contains(Data("4111 1111 1111 1111".utf8).base64EncodedString()))
        #expect(!text.contains(Data("hunter2-password".utf8).base64EncodedString()))
        #expect(!text.contains("4111"))
        #expect(!text.contains("hunter2"))
        #expect(masks.allSatisfy { !text.contains($0) })
        #expect(text.contains(Data("plain note".utf8).base64EncodedString()))
    }

    @Test("a clip from an app Pesto never captures is left out on import and counted")
    func whenFromAnExcludedApp_thenItIsSkipped() async throws {
        let ok = try pngData().base64EncodedString()
        var excluded = item(payloadType: "public.png", payload: ok)
        excluded["sourceBundleID"] = "com.1password.1password"
        let data = try fileJSON(items: [excluded])
        let destination = try side()

        let result = try await destination.exporter.importCollection(from: data, storage: destination.storage)

        #expect(result.itemsImported == 0)
        #expect(result.skippedSensitive == 1)
    }

    // MARK: Bad items

    @Test("an item with broken base64, a wrong kind or a bad payload is rejected on its own")
    func whenAnItemIsMalformed_thenOnlyThatItemIsRejected() async throws {
        let ok = try pngData().base64EncodedString()
        let words = Data("x".utf8).base64EncodedString()
        let link = Data("https://example.com/x".utf8).base64EncodedString()
        let data = try fileJSON(items: [
            item(payloadType: "public.png", payload: "!!! not base64 !!!"),
            item(payloadType: "public.png", payload: Data("not a picture".utf8).base64EncodedString()),
            item(type: "text", payloadType: "public.rtf", payload: words),
            item(type: "file", payloadType: "public.file-url", payload: link),
            item(payloadType: "public.png", payload: ""),
            item(type: "image", payloadType: nil, payload: nil),
            item(payloadType: "public.png", payload: ok)
        ])
        let destination = try side()

        let result = try await destination.exporter.importCollection(from: data, storage: destination.storage)

        #expect(result.itemsImported == 1)
        #expect(result.skippedUnreadable == 5)
        #expect(result.skippedFiles == 1)
        #expect(try clips(destination).count == 1)
    }

    @Test("the kind a file names is never trusted: the payload decides")
    func whenTheTypeIsPlainText_thenTheClipIsText() async throws {
        let words = Data("just words".utf8).base64EncodedString()
        let data = try fileJSON(items: [item(type: "image", payloadType: "public.utf8-plain-text", payload: words)])
        let destination = try side()

        try await destination.exporter.importCollection(from: data, storage: destination.storage)

        #expect(try clips(destination).first?.type == .text)
    }

    @Test("a file reference in a received file is skipped and counted, never made into a clip")
    func whenAFileReferenceArrives_thenNoFileClipIsMade() async throws {
        let path = Data("file:///Users/someone/Documents/report.pdf".utf8).base64EncodedString()
        let data = try fileJSON(items: [item(type: "file", payloadType: "public.file-url", payload: path)])
        let destination = try side()

        let result = try await destination.exporter.importCollection(from: data, storage: destination.storage)

        #expect(result.itemsImported == 0)
        #expect(result.skippedFiles == 1)
        #expect(try clips(destination).isEmpty)
    }

    @Test("a date in the future in a file is brought back to now, so the clip does not stay at the front")
    func whenTheDateIsInTheFuture_thenItIsClamped() async throws {
        let words = Data("from the future".utf8).base64EncodedString()
        var future = item(type: "text", payloadType: "public.utf8-plain-text", payload: words)
        future["timestamp"] = "2999-01-01T00:00:00Z"
        var v1 = item(type: "text", payloadType: nil, payload: nil, preview: "old style, also future")
        v1["timestamp"] = "2999-01-01T00:00:00Z"
        let data = try fileJSON(items: [future, v1])
        let destination = try side()

        let result = try await destination.exporter.importCollection(from: data, storage: destination.storage)

        #expect(result.itemsImported == 2)
        let newest = try #require(clips(destination).map(\.timestamp).max())
        #expect(newest <= .now)
    }

    // MARK: Undo

    @Test("an import with pictures is one action that Undo takes back")
    func whenImportedWithHistory_thenUndoRemovesThePictures() async throws {
        let source = try await source([capture("public.png", pngData())])
        let file = try await source.exporter.exportCollectionFile(id: boardID)
        let history = UndoHistory()
        let container = try ModelContainerSetup.makeInMemory()
        let storage = StorageService(modelContainer: container, environment: .testing { $0.undoHistory = history })

        try await HistoryExporter(modelContainer: container)
            .importCollection(from: file.data, storage: storage, undoHistory: history)
        #expect(history.undoLabel == .importCollection("Mixed"))
        #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).count == 1)

        try await storage.undo()
        #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).isEmpty)
    }
}
