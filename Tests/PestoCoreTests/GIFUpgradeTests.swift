// SPDX-License-Identifier: MIT
import AppKit
import CryptoKit
import SwiftData
import Testing
@testable import PestoCore

private final class FetchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    var requested: [URL] {
        lock.withLock { urls }
    }

    func add(_ url: URL) {
        lock.withLock { urls.append(url) }
    }
}

private func animatedGIF() -> Data {
    SeedFixtures.animatedGIFData(side: 32)
}

private func stillPNG() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )
    return rep?.representation(using: .png, properties: [:]) ?? Data()
}

@Suite("A GIF copied from a browser is fetched and plays", .serialized)
struct GIFUpgradeTests {
    private let container: ModelContainer
    private let service: StorageService
    private let address = URL(string: "https://media.example.com/cats/dance.gif")

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = Self.makeService(container: container, fetching: nil)
    }

    private static func makeService(
        container: ModelContainer, fetching fetcher: (@Sendable (URL) async -> Data?)?
    )
    -> StorageService {
        StorageService(modelContainer: container, environment: .testing {
            $0.textRecognizer = NilRecognizer()
            $0.imageScreener = NeverFlagged()
            $0.remoteGIFFetcher = fetcher
        })
    }

    private func capture(source: URL?) -> PasteboardCapture {
        let png = stillPNG()
        return PasteboardCapture(
            typeIdentifier: "public.png", payload: png,
            contentHash: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(), sourceImageURL: source
        )
    }

    private func onlyItem() throws -> ClipboardItem {
        try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
    }

    @Test("the still picture becomes the GIF when the fetch succeeds, so the card plays and a paste carries it")
    func whenFetched_thenTheClipIsTheGIF() async throws {
        let log = FetchLog()
        let gif = animatedGIF()
        let service = Self.makeService(container: container, fetching: { url in
            log.add(url)
            return gif
        })

        try await service.ingest(capture(source: address))
        await service.waitForBackgroundWork()

        let item = try onlyItem()
        #expect(log.requested == [address])
        #expect(item.blob?.mimeType == "com.compuserve.gif")
        #expect(item.blob?.decryptedData() == gif)
        #expect(item.byteSize == gif.count)
    }

    @Test("nothing is fetched without an address, and a copy that is already a GIF is left alone")
    func whenNoAddressOrAlreadyAGIF_thenNothingIsFetched() async throws {
        let log = FetchLog()
        let service = Self.makeService(container: container, fetching: { url in
            log.add(url)
            return animatedGIF()
        })
        try await service.ingest(capture(source: nil))
        let gifBytes = animatedGIF()
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "com.compuserve.gif", payload: gifBytes,
            contentHash: SHA256.hash(data: gifBytes).map { String(format: "%02x", $0) }.joined(),
            sourceImageURL: address
        ))
        await service.waitForBackgroundWork()

        #expect(log.requested.isEmpty)
    }

    @Test("a failed or refused fetch leaves the still picture as it was")
    func whenTheFetchFails_thenTheStillStays() async throws {
        let service = Self.makeService(container: container, fetching: { _ in nil })

        try await service.ingest(capture(source: address))
        await service.waitForBackgroundWork()

        let item = try onlyItem()
        #expect(item.blob?.mimeType == "public.png")
        #expect(item.type == .image)
    }

    @Test("bytes that are not a GIF are never stored in place of the picture")
    func whenTheBodyIsNotAGIF_thenItIsIgnored() async throws {
        let service = Self.makeService(container: container, fetching: { _ in Data("<html>not a gif</html>".utf8) })

        try await service.ingest(capture(source: address))
        await service.waitForBackgroundWork()

        #expect(try onlyItem().blob?.mimeType == "public.png")
    }

    @Test("without a fetcher (a test host, or the switch off) nothing happens")
    func whenNoFetcher_thenTheStillStays() async throws {
        try await service.ingest(capture(source: address))
        await service.waitForBackgroundWork()
        #expect(try onlyItem().blob?.mimeType == "public.png")
    }

    @Test("a clip deleted while its GIF is on the way stays deleted")
    func whenDeletedMeanwhile_thenNothingComesBack() async throws {
        let service = Self.makeService(container: container, fetching: { _ in
            try? await Task.sleep(for: .milliseconds(100))
            return animatedGIF()
        })
        try await service.ingest(capture(source: address))
        let id = try onlyItem().id
        _ = try await service.deleteItems(ids: [id], reason: .user)

        await service.waitForBackgroundWork()

        #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
    }
}

private struct NilRecognizer: TextRecognizing {
    func recognize(imageData _: Data) async -> String? {
        nil
    }
}

private struct NeverFlagged: ImageSensitivityScreening {
    func isSensitive(imageData _: Data) async -> Bool {
        false
    }
}

@Suite("The watcher reads the address of a copied GIF")
struct GIFAddressCaptureTests {
    @Test("a still picture with an img tag naming a GIF carries that address")
    func whenPNGAndHTML_thenAddressCaptured() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.google.Chrome")
        )
        let captures = CaptureCollector()
        await watcher.onCapture { captures.append($0) }
        let html = "<meta charset='utf-8'><img src=\"https://media.example.com/cats/dance.gif\"/>"

        board.write(
            types: [.png, .html], data: [.png: stillPNG(), .html: Data(html.utf8)], strings: [.html: html]
        )
        await watcher.tick()

        #expect(captures.first?.sourceImageURL?.absoluteString == "https://media.example.com/cats/dance.gif")
    }

    @Test("a picture without such a tag carries none")
    func whenNoHTML_thenNoAddress() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Preview")
        )
        let captures = CaptureCollector()
        await watcher.onCapture { captures.append($0) }

        board.write(types: [.png], data: [.png: stillPNG()])
        await watcher.tick()

        #expect(captures.first?.sourceImageURL == nil)
    }
}
