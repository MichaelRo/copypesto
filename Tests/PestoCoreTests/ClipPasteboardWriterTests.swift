// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import Testing
@testable import PestoCore

@Suite("Filling a pasteboard with a clip")
@MainActor
final class ClipPasteboardWriterTests {
    private let board = NSPasteboard(name: NSPasteboard.Name("net.copypesto.test.\(UUID().uuidString)"))

    isolated deinit {
        board.releaseGlobally()
    }

    private func item(_ type: ClipboardType, preview: String, mime: String? = nil) -> ClipboardItem {
        let item = ClipboardItem(
            type: type, previewText: preview, contentHash: UUID().uuidString, byteSize: preview.utf8.count,
            deviceID: "test", sequenceNumber: 1
        )
        if let mime { item.blob = ClipboardBlob(encryptedData: Data([1]), nonceData: Data([2]), mimeType: mime) }
        return item
    }

    private func fill(
        _ item: ClipboardItem, files: [URL] = [], data: Data? = nil, rich: RichTextPayload? = nil
    )
    -> PasteCoordinator.PayloadKind {
        board.clearContents()
        return ClipPasteboardWriter.fill(board, with: item, fileURLs: files, data: data, richPayload: rich)
    }

    @Test("plain text writes its stored flavour and the string, and types as text")
    func whenPlainText_thenTextPayload() {
        let text = "hello"
        let kind = fill(item(.text, preview: text, mime: "public.utf8-plain-text"), data: Data(text.utf8))

        #expect(kind == .text("hello"))
        #expect(board.string(forType: .string) == "hello")
    }

    @Test("a rich copy gets its formatting back, the plain string, and a rich payload")
    func whenRichText_thenFlavoursAreRestored() {
        let rtf = Data("{\\rtf1 hi}".utf8)
        let kind = fill(
            item(.text, preview: "hi", mime: NSPasteboard.PasteboardType.rtf.rawValue),
            data: rtf, rich: RichTextPayload(html: Data("<b>hi</b>".utf8))
        )

        #expect(kind == .richText(board.string(forType: .string) ?? ""))
        #expect(board.data(forType: .rtf) == rtf)
        #expect(board.data(forType: .html) == Data("<b>hi</b>".utf8))
    }

    @Test("a picture writes its stored data and companion flavours so both Cocoa and Web apps receive full quality")
    func whenPicture_thenCompanionFlavoursWritten() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let kind = fill(item(.image, preview: "Picture", mime: "public.png"), data: png)

        #expect(kind == .nonText)
        #expect(board.data(forType: NSPasteboard.PasteboardType("public.png")) == png)
        #expect(board.data(forType: .tiff) != nil)
    }

    @Test("a TIFF picture writes both TIFF and PNG flavours")
    func whenTIFFPicture_thenBothTIFFAndPNGWritten() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let tiff = try #require(rep.tiffRepresentation)
        let kind = fill(item(.image, preview: "Picture", mime: "public.tiff"), data: tiff)

        #expect(kind == .nonText)
        #expect(board.data(forType: .tiff) == tiff)
        #expect(board.data(forType: .png) != nil)
    }

    @Test("files are written as file URLs and type as non-text")
    func whenFiles_thenFileURLs() {
        let url = URL(fileURLWithPath: "/tmp/pesto-writer-test.txt")
        let kind = fill(item(.file, preview: url.absoluteString), files: [url])

        #expect(kind == .nonText)
        #expect(board.readObjects(forClasses: [NSURL.self])?.compactMap { ($0 as? NSURL)?.path } == [url.path])
    }

    @Test("a clip that never had data falls back to its preview text")
    func whenNoData_thenPreviewIsWritten() {
        #expect(fill(item(.text, preview: "no blob")) == .text("no blob"))
        #expect(board.string(forType: .string) == "no blob")

        #expect(fill(item(.color, preview: "#2F7A49")) == .nonText)
        #expect(board.string(forType: .string) == "#2F7A49")
    }
}
