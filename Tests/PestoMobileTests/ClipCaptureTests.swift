// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PestoCore
@testable import PestoMobile

@Suite("What the person hands Pesto becomes a capture")
struct ClipCaptureTests {
    @Test("a note is plain text with its SHA-256 as the content hash; an empty one is nothing")
    func whenTextIsAdded_thenItIsAPlainTextCapture() throws {
        let capture = try #require(ClipCapture.text("hello"))
        #expect(capture.typeIdentifier == UTType.utf8PlainText.identifier)
        #expect(capture.payloadString == "hello")
        #expect(capture.payload == Data("hello".utf8))
        let expected = SHA256.hash(data: Data("hello".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(capture.contentHash == expected)
        #expect(ClipCapture.text("  \n ") == nil)
    }

    @Test("a link is kept as its address; a file on this device is not a link")
    func whenALinkIsAdded_thenItIsItsAddress() throws {
        let url = try #require(URL(string: "https://copypesto.net/guide"))
        #expect(ClipCapture.link(url)?.payloadString == "https://copypesto.net/guide")
        #expect(ClipCapture.link(URL(fileURLWithPath: "/tmp/a.txt")) == nil)
    }

    @Test("a picture keeps its format when ingest stores that format, and anything else is refused here")
    func whenAPictureIsAdded_thenOnlyStoredFormatsPass() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        #expect(ClipCapture.picture(bytes, typeIdentifier: UTType.png.identifier)?.typeIdentifier == "public.png")
        #expect(ClipCapture.picture(bytes, typeIdentifier: "com.adobe.photoshop-image") == nil)
        #expect(ClipCapture.picture(Data(), typeIdentifier: UTType.png.identifier) == nil)
    }

    @Test("a picture wins over a link, a link over text, and a format ingest cannot store is converted")
    func whenSeveralTypesAreOffered_thenThePreferredOneIsChosen() {
        #expect(ItemProviderCapture
            .choose(typeIdentifiers: ["public.utf8-plain-text", "public.png"]) == .picture("public.png"))
        #expect(ItemProviderCapture
            .choose(typeIdentifiers: ["com.adobe.photoshop-image"]) == .pictureToConvert("com.adobe.photoshop-image"))
        #expect(ItemProviderCapture.choose(typeIdentifiers: ["public.utf8-plain-text", "public.url"]) == .link)
        #expect(ItemProviderCapture.choose(typeIdentifiers: ["public.file-url"]) == nil)
        #expect(ItemProviderCapture.choose(typeIdentifiers: ["public.plain-text"]) == .text)
        #expect(ItemProviderCapture.choose(typeIdentifiers: ["com.example.unknown"]) == nil)
    }

    @Test("a text dropped as an item provider is read and becomes a capture")
    func whenAProviderHoldsText_thenItIsCaptured() async throws {
        let provider = NSItemProvider(object: "dropped words" as NSString)
        let capture = try await ItemProviderCapture.capture(from: [provider])
        #expect(capture?.payloadString == "dropped words")
    }

    @Test("a link handed over as a URL object (Safari's drag, the Paste button) is kept as its whole address")
    func whenAProviderHoldsAURLObject_thenTheAddressIsCaptured() async throws {
        let url = try #require(URL(string: "https://copypesto.net/guide?ref=share"))
        let provider = NSItemProvider(object: url as NSURL)
        let capture = try await ItemProviderCapture.capture(from: [provider])
        #expect(capture?.payloadString == "https://copypesto.net/guide?ref=share")
    }
}
