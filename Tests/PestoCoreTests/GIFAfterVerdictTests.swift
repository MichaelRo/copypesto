// SPDX-License-Identifier: MIT
import AppKit
import CryptoKit
import SwiftData
import Testing
@testable import PestoCore

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    var events: [String] {
        lock.withLock { entries }
    }

    func add(_ event: String) {
        lock.withLock { entries.append(event) }
    }
}

/// Screens slowly and logs what it saw; flags whatever `flags` says.
private struct LoggingScreener: ImageSensitivityScreening {
    let log: EventLog
    let flags: @Sendable (Data) -> Bool

    func isSensitive(imageData: Data) async -> Bool {
        try? await Task.sleep(for: .milliseconds(150))
        log.add(imageData.isGIF ? "screened gif" : "screened still")
        return flags(imageData)
    }
}

/// Reads slowly, so the full verdict lands after the GIF is stored.
private struct SlowRecognizer: TextRecognizing {
    func recognize(imageData _: Data) async -> String? {
        try? await Task.sleep(for: .milliseconds(400))
        return nil
    }
}

@Suite("A browser's GIF is fetched only after the picture's verdict (ADR 0079)", .serialized)
struct GIFAfterVerdictTests {
    private let container: ModelContainer
    private let address = URL(string: "https://media.example.com/cats/dance.gif")
    private let log = EventLog()

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
    }

    private func service(flags: @escaping @Sendable (Data) -> Bool) -> StorageService {
        let log = log
        let gif = SeedFixtures.animatedGIFData(side: 32)
        return StorageService(modelContainer: container, environment: .testing {
            $0.textRecognizer = SlowRecognizer()
            $0.imageScreener = LoggingScreener(log: log, flags: flags)
            $0.nsfwMode = { .blur }
            $0.remoteGIFFetcher = { _ in
                log.add("fetched")
                return gif
            }
        })
    }

    private func capture() -> PasteboardCapture {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        let png = rep?.representation(using: .png, properties: [:]) ?? Data()
        return PasteboardCapture(
            typeIdentifier: "public.png", payload: png,
            contentHash: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(), sourceImageURL: address
        )
    }

    private func onlyItem() throws -> ClipboardItem {
        try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
    }

    @Test("the GIF is not fetched until the still picture is screened, and a clean GIF is screened before it is kept")
    func whenStillPasses_thenTheGIFIsFetchedAfterAndScreened() async throws {
        let service = service(flags: { _ in false })
        try await service.ingest(capture())
        await service.waitForBackgroundWork()

        #expect(log.events == ["screened still", "fetched", "screened gif"])
        let item = try onlyItem()
        #expect(item.blob?.mimeType == "com.compuserve.gif")
        #expect(!item.isNSFW)
    }

    @Test("a GIF the model flags is kept for Show and the clip is flagged, even after the picture's text is read")
    func whenGIFIsFlagged_thenItIsKeptAndTheClipStaysFlagged() async throws {
        let service = service(flags: { $0.isGIF })
        try await service.ingest(capture())
        await service.waitForBackgroundWork()

        let item = try onlyItem()
        #expect(item.blob?.mimeType == "com.compuserve.gif")
        #expect(item.isNSFW)
        #expect(!item.analysisPending)
    }

    @Test("a flagged still still gets its GIF, unscreened, so Show plays it")
    func whenStillIsFlagged_thenTheGIFIsFetchedAndTheClipStaysFlagged() async throws {
        let service = service(flags: { _ in true })
        try await service.ingest(capture())
        await service.waitForBackgroundWork()

        #expect(log.events == ["screened still", "fetched"])
        let item = try onlyItem()
        #expect(item.blob?.mimeType == "com.compuserve.gif")
        #expect(item.isNSFW)
    }
}
