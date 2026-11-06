// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import Testing
@testable import PestoCore

@MainActor
@Suite("JSON and Markdown entries: which clips qualify, and what they write")
struct StructuredPasteTests {
    private func clip(
        _ text: String, type: ClipboardType = .text, rich: RichTextPayload? = nil, byteSize: Int? = nil,
        withBlob: Bool = true, language: String? = nil
    )
    throws -> ClipboardItem {
        let item = ClipboardItem(
            type: type, previewText: withBlob ? "" : text, contentHash: UUID().uuidString,
            byteSize: byteSize ?? text.utf8.count, deviceID: "test", sequenceNumber: 1
        )
        item.detectedLanguage = language
        guard withBlob else { return item }
        let aad = BlobEncryption.associatedData(itemID: item.id, field: .blob)
        let sealed = try BlobEncryption().encrypt(Data(text.utf8), associatedData: aad)
        let blob = ClipboardBlob(
            encryptedData: sealed.ciphertext,
            nonceData: sealed.nonce,
            mimeType: "public.utf8-plain-text"
        )
        blob.aadBound = true
        if let rich {
            let richSealed = try BlobEncryption().encrypt(JSONEncoder().encode(rich), associatedData: aad)
            blob.encryptedRichData = richSealed.ciphertext
            blob.richNonceData = richSealed.nonce
        }
        item.blob = blob
        return item
    }

    private let table = "<table><tr><th>Name</th><th>N</th></tr><tr><td>Ana</td><td>1</td></tr></table>"
    private let expectedTable = "| Name | N |\n| --- | --- |\n| Ana | 1 |"

    // MARK: JSON

    @Test("comma separated rows and a compact document are offered JSON, and write it")
    func whenTableOrCompactJSON_thenJSON() throws {
        let csv = try clip("name,age\nAna,30\nBo,25")
        #expect(StructuredPaste.offered(for: csv) == [.json])
        #expect(StructuredPaste.result(of: .json, for: csv)?.hasPrefix("[\n  {\n    \"name\": \"Ana\"") == true)
        let json = try clip("{\"b\":1,\"a\":2}", type: .code, language: "json")
        #expect(StructuredPaste.offered(for: json) == [.json])
        #expect(StructuredPaste.result(of: .json, for: json) == "{\n  \"b\": 1,\n  \"a\": 2\n}")
    }

    @Test("a document that is already indented, prose and a word offer nothing")
    func whenNothingToDo_thenNothing() throws {
        #expect(try StructuredPaste.offered(for: clip("{\n  \"a\": 1\n}", type: .code, language: "json")).isEmpty)
        #expect(try StructuredPaste.offered(for: clip("Well, yes. It is a sentence, with commas.")).isEmpty)
        #expect(try StructuredPaste.offered(for: clip("word")).isEmpty)
    }

    // MARK: Markdown

    @Test("a clip that kept HTML with a table is offered Markdown, and writes the table")
    func whenHTMLTable_thenMarkdown() throws {
        let item = try clip("Name\tN\nAna\t1", rich: RichTextPayload(html: Data(table.utf8)))
        #expect(StructuredPaste.offered(for: item) == [.json, .markdown])
        #expect(StructuredPaste.result(of: .markdown, for: item) == expectedTable)
    }

    @Test("a clip that kept only RTF is read from the RTF")
    func whenRTFOnly_thenMarkdown() throws {
        let bold = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .boldFontMask)
        let document = NSAttributedString(string: "strong\n", attributes: [.font: bold])
        let data = try document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let item = try clip("strong", rich: RichTextPayload(rtf: data))
        #expect(StructuredPaste.offered(for: item) == [.markdown])
        #expect(StructuredPaste.result(of: .markdown, for: item) == "**strong**")
    }

    @Test("HTML with no structure falls back to the RTF flavour, then to nothing")
    func whenHTMLPlain_thenNextFlavour() throws {
        let item = try clip("hello", rich: RichTextPayload(html: Data("<span>hello</span>".utf8)))
        #expect(StructuredPaste.offered(for: item).isEmpty)
    }

    @Test("copied HTML source, a code clip in the HTML language, can be written as Markdown")
    func whenHTMLSource_thenMarkdown() throws {
        let item = try clip(table, type: .code, language: "html")
        #expect(StructuredPaste.result(of: .markdown, for: item) == expectedTable)
    }

    @Test("these transforms are not made here")
    func whenOtherTransform_thenNil() throws {
        let item = try clip("a,b\n1,2")
        #expect(StructuredPaste.result(of: .uppercase, for: item) == nil)
        #expect(StructuredPaste.result(of: .markdown, for: item) == nil)
    }

    // MARK: What is never read

    @Test("a hidden clip is not offered anything, shown or not, and nothing is written for it")
    func whenSecret_thenNothing() throws {
        let secret = try clip("name,key\nAna,sk-live-123", rich: RichTextPayload(html: Data(table.utf8)))
        secret.sensitivityRaw = SensitivityCategory.apiKey.rawValue
        #expect(StructuredPaste.offered(for: secret).isEmpty)
        #expect(StructuredPaste.result(of: .json, for: secret) == nil)
        #expect(StructuredPaste.result(of: .markdown, for: secret) == nil)
    }

    @Test("a filtered clip and one still being screened are not offered anything")
    func whenFilteredOrPending_thenNothing() throws {
        let filtered = try clip("a,b\n1,2")
        filtered.isNSFW = true
        let pending = try clip("a,b\n1,2")
        pending.analysisPending = true
        #expect(StructuredPaste.offered(for: filtered).isEmpty)
        #expect(StructuredPaste.offered(for: pending).isEmpty)
        #expect(StructuredPaste.result(of: .json, for: pending) == nil)
    }

    @Test("a clip over the size limit is not read, however its text looks")
    func whenTooBig_thenNothing() throws {
        let big = try clip("a,b\n1,2", byteSize: StructuredPaste.maxClipBytes + 1)
        #expect(StructuredPaste.offered(for: big).isEmpty)
        #expect(StructuredPaste.result(of: .json, for: big) == nil)
    }

    @Test("a clip whose blob is missing or will not open is never answered from its preview")
    func whenBlobUnavailable_thenNothing() throws {
        let noBlob = try clip("a,b\n1,2", withBlob: false)
        #expect(noBlob.displayPreviewText.contains("a,b"))
        #expect(StructuredPaste.offered(for: noBlob).isEmpty)
        let broken = try clip("a,b\n1,2")
        broken.blob?.encryptedData = Data(repeating: 7, count: 40)
        #expect(StructuredPaste.offered(for: broken).isEmpty)
        #expect(StructuredPaste.result(of: .json, for: broken) == nil)
    }

    @Test("pictures, files, links and colors have no entry")
    func whenOtherKinds_thenNothing() throws {
        for type in [ClipboardType.image, .file, .url, .color] {
            #expect(try StructuredPaste.offered(for: clip("a,b\n1,2", type: type)).isEmpty)
        }
    }

    @Test("a sealed rich payload past its limit is not decrypted for the menu")
    func whenRichPayloadHuge_thenNoMarkdown() throws {
        let item = try clip("x", rich: RichTextPayload(html: Data(table.utf8)))
        item.blob?.encryptedRichData = Data(repeating: 1, count: StructuredPaste.maxRichCiphertextBytes + 1)
        #expect(StructuredPaste.offered(for: item).isEmpty)
    }
}
