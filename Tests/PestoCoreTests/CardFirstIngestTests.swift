// SPDX-License-Identifier: MIT
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

/// Lets a stand-in for the slow work (reading the text in a picture, asking the on-device model) be held until the test
/// has looked at the clip as it is while that work runs.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if !isOpen { waiting.append(continuation) }
                return isOpen
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let toResume = lock.withLock {
            isOpen = true
            defer { waiting = [] }
            return waiting
        }
        toResume.forEach { $0.resume() }
    }
}

private struct HeldRecognizer: TextRecognizing {
    let gate: Gate
    let text: String?

    func recognize(imageData _: Data) async -> String? {
        await gate.wait()
        return text
    }
}

private struct HeldScreener: ImageSensitivityScreening {
    let gate: Gate
    let verdict: Bool

    func isSensitive(imageData _: Data) async -> Bool {
        await gate.wait()
        return verdict
    }
}

private final class SpyLastItemStore: LastItemStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var written: [UUID] = []

    var ids: [UUID] {
        lock.withLock { written }
    }

    func write(id: UUID, preview _: String, type _: String, timestamp _: Date, sourceApp _: String?) {
        lock.withLock { written.append(id) }
    }

    func clear() {}
    func clear(ifItemID _: UUID) {}
}

@Suite("A copy shows at once and is judged afterwards", .serialized)
struct CardFirstIngestTests {
    private let container: ModelContainer
    private let service: StorageService
    private let lastItem = SpyLastItemStore()

    init() async throws {
        container = try ModelContainerSetup.makeInMemory().synced
        let spy = lastItem
        service = StorageService(modelContainer: container, environment: .testing { $0.lastItemStore = spy })
        AppDefaults.store.set(NSFWMode.blur.rawValue, forKey: NSFWMode.defaultsKey)
    }

    /// A service over the same store whose picture reading and screening wait on `gate`.
    private func held(_ gate: Gate, text: String?, verdict: Bool) -> StorageService {
        let spy = lastItem
        return StorageService(modelContainer: container, environment: .testing {
            $0.lastItemStore = spy
            $0.textRecognizer = HeldRecognizer(gate: gate, text: text)
            $0.imageScreener = HeldScreener(gate: gate, verdict: verdict)
        })
    }

    private func png() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(
            red: Double.random(in: 0...1),
            green: Double.random(in: 0...1),
            blue: 0.7,
            alpha: 1
        ))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        try CGImageDestinationAddImage(destination, #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func pictureCapture() throws -> PasteboardCapture {
        let data = try png()
        return PasteboardCapture(
            typeIdentifier: "public.png", payload: data,
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func textCapture(_ text: String) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func onlyItem() throws -> ClipboardItem {
        try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
    }

    @Test("a picture is saved before it has been read, with nothing readable stored")
    func whenPictureCopied_thenSavedPendingWithNoPreview() async throws {
        let gate = Gate()
        let service = held(gate, text: "meeting notes", verdict: false)

        try await service.ingest(pictureCapture())

        let item = try onlyItem()
        #expect(item.analysisPending)
        #expect(item.previewText.isEmpty)
        #expect(item.previewCiphertext == nil)
        #expect(item.sensitivityRaw == nil)
        #expect(lastItem.ids.isEmpty, "the last-item file must not describe a clip nobody has judged")
        gate.open()
        await service.waitForBackgroundWork()
    }

    @Test("when the reading finishes the text is searchable, the clip is uncovered, and the last-item file follows")
    func whenAnalysisFinishes_thenTheClipIsResolved() async throws {
        let gate = Gate()
        let service = held(gate, text: "meeting notes for Friday", verdict: false)
        try await service.ingest(pictureCapture())

        gate.open()
        await service.waitForBackgroundWork()

        let item = try onlyItem()
        #expect(!item.analysisPending)
        #expect(item.displayPreviewText == "meeting notes for Friday")
        #expect(item.isNSFW == false)
        #expect(lastItem.ids == [item.id])
    }

    @Test("a secret read out of a picture is masked when the reading finishes, and never stored readable")
    func whenThePictureHoldsASecret_thenItIsMasked() async throws {
        let gate = Gate()
        let key = "sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef"
        let service = held(gate, text: "token \(key)", verdict: false)
        try await service.ingest(pictureCapture())
        gate.open()
        await service.waitForBackgroundWork()

        let item = try onlyItem()
        #expect(item.sensitivity != nil)
        #expect(!item.gridPreview.contains("EXAMPLEEXAMPLE"))
        #expect(!item.previewText.contains("EXAMPLEEXAMPLE"))
        #expect(lastItem.ids.isEmpty, "a secret is never written to the last-item file")
    }

    @Test("a picture the model refuses is flagged when the judging finishes")
    func whenTheModelFlagsThePicture_thenItIsMarked() async throws {
        let gate = Gate()
        let service = held(gate, text: nil, verdict: true)
        try await service.ingest(pictureCapture())
        #expect(
            try onlyItem().isNSFW == false,
            "it is covered by the pending mark, not by the verdict, until the verdict"
        )

        gate.open()
        await service.waitForBackgroundWork()

        #expect(try onlyItem().isNSFW)
        #expect(try !onlyItem().analysisPending)
    }

    @Test("a large text is saved at once and its secrets are found afterwards")
    func whenLargeTextCopied_thenScannedAfterwards() async throws {
        let card = "4242 4242 4242 4242"
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 8000)
        try await service.ingest(textCapture("my card is \(card) thanks " + filler))

        let pending = try onlyItem()
        #expect(pending.analysisPending)
        #expect(pending.previewText.isEmpty && pending.previewCiphertext == nil)

        await service.waitForBackgroundWork()
        let done = try onlyItem()
        #expect(!done.analysisPending)
        #expect(done.sensitivity != nil, "the card number at the start of 200 KB is still found")
        #expect(!done.gridPreview.contains("4242 4242"))
    }

    @Test("a short text, a link and a colour are judged before they are saved, as they always were")
    func whenShortTextCopied_thenNoPendingState() async throws {
        try await service.ingest(textCapture("4242 4242 4242 4242"))
        let item = try onlyItem()
        #expect(!item.analysisPending)
        #expect(item.sensitivity != nil)
    }

    @Test("a clip deleted while it is being judged stays deleted")
    func whenDeletedDuringAnalysis_thenNothingComesBack() async throws {
        let gate = Gate()
        let service = held(gate, text: "gone", verdict: false)
        try await service.ingest(pictureCapture())
        let id = try onlyItem().id
        _ = try await service.deleteItems(ids: [id], reason: .user)

        gate.open()
        await service.waitForBackgroundWork()

        #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
    }

    @Test("a clip still pending when the app quit is judged the next time it starts")
    func whenLeftPending_thenResumedAtLaunch() async throws {
        let gate = Gate()
        let service = held(gate, text: "left over", verdict: false)
        try await service.ingest(pictureCapture())
        gate.open()
        await service.waitForBackgroundWork()
        let item = try onlyItem()
        let context = ModelContext(container)
        let stored = try #require(try context.fetch(FetchDescriptor<ClipboardItem>()).first)
        stored.analysisPending = true
        stored.previewText = ""
        stored.previewCiphertext = nil
        stored.previewNonce = nil
        try context.save()

        let relaunched = held(gate, text: "left over", verdict: false)
        await relaunched.resumePendingAnalysis()
        await relaunched.waitForBackgroundWork()

        let resumed = try onlyItem()
        #expect(resumed.id == item.id)
        #expect(!resumed.analysisPending)
        #expect(resumed.displayPreviewText == "left over")
    }

    @Test("a backup leaves out a clip nobody has judged yet")
    func whenBackedUpWhilePending_thenSkipped() async throws {
        let gate = Gate()
        let service = held(gate, text: "x", verdict: false)
        try await service.ingest(pictureCapture())

        let collected = RecordCounter()
        let summary = try await service.streamBackupRecords(includeSensitive: true, sink: { _ in collected.add() })

        #expect(summary.items == 0)
        #expect(collected.isEmpty)
        gate.open()
        await service.waitForBackgroundWork()
    }
}

private final class RecordCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0

    var count: Int {
        lock.withLock { total }
    }

    var isEmpty: Bool {
        lock.withLock { total == 0 }
    }

    func add() {
        lock.withLock { total += 1 }
    }
}
