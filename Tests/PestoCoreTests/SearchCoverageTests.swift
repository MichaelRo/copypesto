// SPDX-License-Identifier: MIT
import AppKit
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

private struct FixedRecognizer: TextRecognizing {
    let text: String?
    func recognize(imageData _: Data) async -> String? {
        text
    }
}

private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Draws `text` black on white into a PNG large enough for Vision.
private func renderedPNG(text: String) throws -> Data {
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 120, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 600, height: 120).fill()
    (text as NSString).draw(at: NSPoint(x: 16, y: 30), withAttributes: [
        .font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black
    ])
    NSGraphicsContext.restoreGraphicsState()
    return try #require(rep.representation(using: .png, properties: [:]))
}

@Suite("Search reaches every kind of clip", .serialized)
@MainActor
struct SearchCoverageTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
    }

    private func service(_ configure: @escaping @Sendable (inout StorageEnvironment) -> Void = { _ in })
        -> StorageService
    {
        StorageService(modelContainer: container, environment: .testing {
            $0.nsfwMode = { .show }
            configure(&$0)
        })
    }

    private func matches(_ query: String) throws -> [ClipboardItem] {
        let items = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        let ids = Set(HistoryIndex(items: items).matching(HistoryCriteria(searchActive: true, query: query)))
        return items.filter { ids.contains($0.id) }
    }

    private func textCapture(_ text: String, type: String = "public.utf8-plain-text") -> PasteboardCapture {
        let data = Data(text.utf8)
        return PasteboardCapture(typeIdentifier: type, payload: data, payloadString: text, contentHash: hash(data))
    }

    private func pictureCapture(_ png: Data) -> PasteboardCapture {
        PasteboardCapture(typeIdentifier: "public.png", payload: png, contentHash: hash(png))
    }

    private func anyPNG() throws -> Data {
        try renderedPNG(text: String(UUID().uuidString.prefix(8)))
    }

    @Test("text is found by its content")
    func whenTextIngested_thenSearchFindsIt() async throws {
        let service = service()
        try await service.ingest(textCapture("the quarterly invoice for Acme"))
        await service.waitForBackgroundWork()
        #expect(try matches("invoice").count == 1)
        #expect(try matches("Acme").count == 1)
        #expect(try matches("zebra").isEmpty)
    }

    @Test("code is found by its content")
    func whenCodeIngested_thenSearchFindsIt() async throws {
        let service = service()
        try await service.ingest(textCapture("func fetchUserProfile() -> Profile { return Profile() }"))
        await service.waitForBackgroundWork()
        let found = try matches("fetchUserProfile")
        #expect(found.count == 1)
        #expect(found.first?.type == .code)
    }

    @Test("a link is found by its address")
    func whenLinkIngested_thenSearchFindsTheAddress() async throws {
        let service = service()
        try await service.ingest(textCapture("https://example.com/pricing/enterprise", type: "public.url"))
        await service.waitForBackgroundWork()
        #expect(try matches("pricing/enterprise").count == 1)
    }

    @Test("a link is found by the page title and site name fetched for its preview")
    func whenLinkHasPreview_thenSearchFindsItsTitleAndSite() async throws {
        let service = service()
        try await service.ingest(textCapture("https://example.com/p/8812", type: "public.url"))
        await service.waitForBackgroundWork()
        let context = ModelContext(container)
        let item = try #require(try context.fetch(FetchDescriptor<ClipboardItem>()).first)
        item.ogTitle = "Sourdough starter guide"
        item.ogSiteName = "Bakers Weekly"
        try context.save()
        #expect(try matches("sourdough").count == 1)
        #expect(try matches("bakers weekly").count == 1)
        #expect(try matches("pizza").isEmpty)
    }

    @Test("a file is found by its path and name")
    func whenFileIngested_thenSearchFindsThePath() async throws {
        let service = service()
        try await service.ingest(textCapture("/Users/me/Documents/tax-return-2025.pdf", type: "public.file-url"))
        await service.waitForBackgroundWork()
        let found = try matches("tax-return")
        #expect(found.count == 1)
        #expect(found.first?.type == .file)
    }

    @Test("a color is found by its value")
    func whenColorIngested_thenSearchFindsIt() async throws {
        let service = service()
        try await service.ingest(textCapture("#3A7BD5"))
        await service.waitForBackgroundWork()
        #expect(try matches("3a7bd5").count == 1)
    }

    @Test("a picture is found by the text read inside it once the reading has finished")
    func whenPictureIngested_thenSearchFindsItsText() async throws {
        let service = service { $0.textRecognizer = FixedRecognizer(text: "Boarding pass gate B22 to Lisbon") }
        try await service.ingest(pictureCapture(anyPNG()))
        await service.waitForBackgroundWork()
        let found = try matches("lisbon")
        #expect(found.count == 1)
        #expect(found.first?.type == .image)
        #expect(try matches("gate b22").count == 1)
    }

    @Test("a picture still being read matches nothing, and the finished reading updates the same index")
    func whenPictureStillPending_thenNotYetSearchable() async throws {
        let service = service { $0.textRecognizer = FixedRecognizer(text: "Lisbon") }
        try await service.ingest(pictureCapture(anyPNG()))
        let pending = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        if pending.analysisPending { #expect(try matches("lisbon").isEmpty) }
        await service.waitForBackgroundWork()
        #expect(try matches("lisbon").count == 1)
    }

    @Test("a picture with no text, or with its reading switched off, matches only its title, note and tags")
    func whenPictureHasNoText_thenOnlyMetadataMatches() async throws {
        let service = service { $0.textRecognizer = FixedRecognizer(text: nil) }
        try await service.ingest(pictureCapture(anyPNG()))
        await service.waitForBackgroundWork()
        let context = ModelContext(container)
        let item = try #require(try context.fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(try matches("lisbon").isEmpty)
        item.updateMetadata {
            $0.customTitle = "Lisbon trip"
            $0.tags = ["travel"]
        }
        try context.save()
        #expect(try matches("lisbon").count == 1)
        #expect(try matches("@travel").count == 1)
    }

    @Test("text read inside a picture that holds a secret is masked and never searchable")
    func whenPictureHoldsSecret_thenItsTextIsNotSearchable() async throws {
        let key = "sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef"
        let service = service { $0.textRecognizer = FixedRecognizer(text: "token \(key) for the server") }
        try await service.ingest(pictureCapture(anyPNG()))
        await service.waitForBackgroundWork()
        #expect(try matches("EXAMPLEEXAMPLE").isEmpty)
        #expect(try matches("for the server").isEmpty)
    }

    @Test(
        "the real Vision reader makes a rendered screenshot searchable",
        .enabled(if: VisionAvailability.canRecognizeText, "text recognition needs a real Mac")
    )
    func whenRealPictureIngested_thenSearchFindsItsWords() async throws {
        let service = service { $0.textRecognizer = OCRService() }
        try await service.ingest(pictureCapture(renderedPNG(text: "Invoice 4821 Acme Corp")))
        await service.waitForBackgroundWork()
        #expect(try matches("acme").count == 1)
        #expect(try matches("4821").count == 1)
    }
}
