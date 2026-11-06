// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import Testing
@testable import PestoCore

/// What opening a clip's menu and pasting cost at the largest clip each entry will read. `swift test` builds without
/// optimization, so the budgets here are about ten times the release numbers recorded in ADR 0033 and only catch a
/// change that makes a step much slower; on CI the numbers are printed only.
@MainActor
@Suite("JSON and Markdown entries: cost at the limits")
struct StructuredPastePerformanceTests {
    private func sealed(_ text: String, rich: RichTextPayload? = nil) throws -> ClipboardItem {
        let item = ClipboardItem(
            type: .text, previewText: "", contentHash: UUID().uuidString, byteSize: text.utf8.count,
            deviceID: "test", sequenceNumber: 1
        )
        let aad = BlobEncryption.associatedData(itemID: item.id, field: .blob)
        let box = try BlobEncryption().encrypt(Data(text.utf8), associatedData: aad)
        let blob = ClipboardBlob(
            encryptedData: box.ciphertext,
            nonceData: box.nonce,
            mimeType: "public.utf8-plain-text"
        )
        blob.aadBound = true
        if let rich {
            let richBox = try BlobEncryption().encrypt(JSONEncoder().encode(rich), associatedData: aad)
            blob.encryptedRichData = richBox.ciphertext
            blob.richNonceData = richBox.nonce
        }
        item.blob = blob
        return item
    }

    private func measure(_ label: String, budget: Duration, _ work: () -> Void) {
        work() // warm
        let start = ContinuousClock.now
        work()
        let elapsed = ContinuousClock.now - start
        // swiftlint:disable:next no_print_in_release
        print("PERF structured \(label): \(elapsed)")
        if ProcessInfo.processInfo.environment["CI"] == nil { #expect(elapsed < budget, "\(label) took \(elapsed)") }
    }

    private func spreadsheet(bytes: Int) -> String {
        var text = "name\temail\tcity\tdate\tamount\n"
        while text.utf8.count < bytes {
            text += "Ana Example\tana@example.com\tOslo, Norway\t2024-01-01\t123.45\n"
        }
        return text
    }

    private func htmlTable(bytes: Int) -> Data {
        var html = "<table><tr><th>Name</th><th>Link</th><th>N</th></tr>"
        while html.utf8.count < bytes {
            html += "<tr><td><b>Ana</b></td><td><a href=\"https://example.com/a?x=1\">link</a> &amp; text</td><td>12,345</td></tr>"
        }
        return Data((html + "</table>").utf8)
    }

    @Test("opening the menu on a 1 MB spreadsheet copy")
    func menuOnLargeSpreadsheet() throws {
        let item = try sealed(spreadsheet(bytes: 990_000))
        measure("menu, 1 MB TSV", budget: .milliseconds(20)) { _ = StructuredPaste.offered(for: item) }
        measure("paste, 1 MB TSV", budget: .milliseconds(400)) { _ = StructuredPaste.result(of: .json, for: item) }
    }

    @Test("opening the menu on 1 MB of compact JSON")
    func menuOnLargeJSON() throws {
        var text = "["
        while text.utf8.count < 990_000 {
            text += "{\"name\":\"Ana\",\"tags\":[\"a\",\"b\"],\"n\":12345},"
        }
        let item = try sealed(text + "{}]")
        measure("menu, 1 MB JSON", budget: .milliseconds(400)) { _ = StructuredPaste.offered(for: item) }
        measure("paste, 1 MB JSON", budget: .milliseconds(400)) { _ = StructuredPaste.result(of: .json, for: item) }
    }

    @Test("opening the menu on an HTML table at the limit")
    func menuOnLargeHTML() throws {
        let item = try sealed("plain", rich: RichTextPayload(html: htmlTable(bytes: HTMLMarkdown.maxInputBytes - 1000)))
        measure("menu, HTML at the limit", budget: .milliseconds(250)) { _ = StructuredPaste.offered(for: item) }
        measure("paste, HTML at the limit", budget: .milliseconds(250)) { _ = StructuredPaste.result(
            of: .markdown,
            for: item
        ) }
    }

    @Test("opening the menu on a clip with RTF at the limit")
    func menuOnLargeRTF() throws {
        let bold = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .boldFontMask)
        let document = NSMutableAttributedString()
        var index = 0
        while true {
            document.append(NSAttributedString(
                string: "word\(index) ",
                attributes: [.font: NSFont.systemFont(ofSize: 13)]
            ))
            document.append(NSAttributedString(string: "strong\(index)\n", attributes: [.font: bold]))
            index += 1
            if index % 20 == 0,
               let data = try? document.data(
                   from: NSRange(location: 0, length: document.length),
                   documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
               ), data.count > RTFMarkdown.maxInputBytes - 3000 { break }
        }
        let data = try document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        #expect(data.count <= RTFMarkdown.maxInputBytes)
        let item = try sealed("plain", rich: RichTextPayload(rtf: data))
        measure("menu, \(data.count / 1000) KB RTF", budget: .milliseconds(100)) {
            _ = StructuredPaste.offered(for: item)
        }
    }
}
