// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import Testing
@testable import PestoCore

@MainActor
@Suite("StructuredPaste real-app pasteboard dumps", .serialized)
struct StructuredPasteDumpTests {
    private func captureFixture(_ filename: String) async throws -> PasteboardCapture {
        let fixture = try PasteboardDumpFixture.load(named: filename)
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: fixture.sourceBundleID)
        )
        let collector = CaptureCollector()
        await watcher.onCapture { collector.append($0) }
        fixture.write(to: board)
        await watcher.tick()
        return try #require(collector.first, "expected capture for \(filename)")
    }

    private func makeItem(from capture: PasteboardCapture) throws -> ClipboardItem {
        let text = try #require(capture.payloadString)
        let item = ClipboardItem(
            type: .text, previewText: "", contentHash: UUID().uuidString,
            byteSize: text.utf8.count, deviceID: "test", sequenceNumber: 1
        )
        let aad = BlobEncryption.associatedData(itemID: item.id, field: .blob)
        let sealed = try BlobEncryption().encrypt(Data(text.utf8), associatedData: aad)
        let blob = ClipboardBlob(
            encryptedData: sealed.ciphertext,
            nonceData: sealed.nonce,
            mimeType: capture.typeIdentifier
        )
        blob.aadBound = true
        if let rich = capture.richPayload {
            let richSealed = try BlobEncryption().encrypt(JSONEncoder().encode(rich), associatedData: aad)
            blob.encryptedRichData = richSealed.ciphertext
            blob.richNonceData = richSealed.nonce
        }
        item.blob = blob
        return item
    }

    @Test("Spreadsheet and web table dumps capture and produce Paste As JSON and Markdown conversions")
    func whenTableDumpsCaptured_thenStructuredPasteOffersConversions() async throws {
        for filename in ["excel-table.json", "numbers-table.json", "web-table.json"] {
            let captured = try await captureFixture(filename)
            let item = try makeItem(from: captured)
            let offered = StructuredPaste.offered(for: item)
            #expect(offered.contains(.json), "expected JSON Paste As option for \(filename)")
            #expect(StructuredPaste.result(of: .json, for: item) != nil, "expected JSON output for \(filename)")
        }
    }

    @Test("Rich text dumps from Pages, Notes, and Google Docs capture and convert to Markdown")
    func whenRichTextDumpsCaptured_thenMarkdownProduced() async throws {
        for filename in ["pages-rich-text.json", "notes-list.json", "google-docs.json"] {
            let captured = try await captureFixture(filename)
            let item = try makeItem(from: captured)
            let offered = StructuredPaste.offered(for: item)
            #expect(offered.contains(.markdown), "expected Markdown Paste As option for \(filename)")
            let md = try #require(StructuredPaste.result(of: .markdown, for: item))
            #expect(!md.isEmpty, "expected non-empty Markdown for \(filename)")
        }
    }
}
