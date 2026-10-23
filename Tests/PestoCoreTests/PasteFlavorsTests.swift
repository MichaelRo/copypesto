// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("PasteFlavors")
@MainActor
struct PasteFlavorsTests {
    @Test("a stored URL also yields its text, for fields that ignore public.url")
    func whenStoredURL_thenTextFlavourIsTheURLString() {
        let data = Data("https://example.com/a?b=1".utf8)

        #expect(PasteFlavors.plainText(forStoredType: "public.url", data: data) == "https://example.com/a?b=1")
    }

    @Test("stored RTF from before rich text was flattened yields its plain text, not markup")
    func whenStoredRTF_thenTextFlavourIsFlattened() throws {
        let attributed = NSAttributedString(string: "legacy note")
        let rtf = try #require(attributed.rtf(from: NSRange(location: 0, length: attributed.length)))

        #expect(PasteFlavors.plainText(forStoredType: "public.rtf", data: rtf) == "legacy note")
    }

    @Test("plain text, images and files need no extra flavour")
    func whenAlreadyTextOrNotTextual_thenNoExtraFlavour() {
        let data = Data("x".utf8)

        #expect(PasteFlavors.plainText(forStoredType: "public.utf8-plain-text", data: data) == nil)
        #expect(PasteFlavors.plainText(forStoredType: "public.png", data: data) == nil)
        #expect(PasteFlavors.plainText(forStoredType: "public.file-url", data: data) == nil)
    }
}
