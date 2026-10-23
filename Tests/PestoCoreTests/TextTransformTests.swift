// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("TextTransform (Paste as…)")
struct TextTransformTests {
    // MARK: Case and lines

    @Test("case changes", arguments: [
        (TextTransform.uppercase, "hello Wörld", "HELLO WÖRLD"),
        (.lowercase, "HeLLo WÖRLD", "hello wörld"),
        (.titleCase, "the quick brown fox", "The Quick Brown Fox"),
        (.sentenceCase, "hELLO wORLD. bYE", "Hello world. bye"),
        (.stripFormatting, "already plain", "already plain")
    ])
    func whenCaseTransform_thenExpected(transform: TextTransform, input: String, expected: String) {
        #expect(transform.apply(to: input) == expected)
    }

    @Test("line operations", arguments: [
        (TextTransform.trimWhitespace, "  \n hi there \n ", "hi there"),
        (.unwrapLines, "one\n  two \n\n three", "one two three"),
        (.removeDuplicateLines, "a\nb\na\nc\nb", "a\nb\nc"),
        (.sortLinesAZ, "pear\napple\nfig", "apple\nfig\npear"),
        (.sortLinesZA, "apple\nfig\npear", "pear\nfig\napple"),
        (.reverseLines, "1\n2\n3", "3\n2\n1")
    ])
    func whenLineTransform_thenExpected(transform: TextTransform, input: String, expected: String) {
        #expect(transform.apply(to: input) == expected)
    }

    // MARK: Encoders and formatters

    @Test("JSON pretty-print produces the same document, indented")
    func whenJSONPrettyPrinted_thenSameDataMultiLine() throws {
        let pretty = TextTransform.jsonPrettyPrint.apply(to: "{\"name\":\"pesto\",\"n\":[1,2]}")
        #expect(pretty.contains("\n"))
        let original = try JSONSerialization
            .jsonObject(with: Data("{\"name\":\"pesto\",\"n\":[1,2]}".utf8)) as? NSDictionary
        let reparsed = try JSONSerialization.jsonObject(with: Data(pretty.utf8)) as? NSDictionary
        #expect(original == reparsed)
    }

    @Test("JSON minify removes whitespace")
    func whenJSONMinified_thenNoWhitespace() {
        #expect(TextTransform.jsonMinify.apply(to: "{ \"a\" :\n 1 }") == "{\"a\":1}")
    }

    @Test("text that is not JSON is left alone")
    func whenNotJSON_thenUnchanged() {
        #expect(TextTransform.jsonPrettyPrint.apply(to: "just words") == "just words")
        #expect(TextTransform.jsonMinify.apply(to: "{broken") == "{broken")
    }

    @Test("HTML tags are removed and common entities decoded")
    func whenHTML_thenPlainText() {
        #expect(TextTransform.stripHTML.apply(to: "<p>Fish &amp; <b>chips</b> &lt;3</p>") == "Fish & chips <3")
    }

    @Test("HTML that ends with a tag does not crash, and no character next to a tag is lost")
    func whenHTMLEndsWithATag_thenNoCrashAndNoLoss() {
        #expect(TextTransform.stripHTML.apply(to: "<b>bold</b>") == "bold")
        #expect(TextTransform.stripHTML.apply(to: "a<br>b<br>c") == "abc")
        #expect(TextTransform.stripHTML.apply(to: "<p>Hello</p>") == "Hello")
    }

    @Test("Base64 round-trips, including non-ASCII text")
    func whenBase64_thenRoundTrips() {
        #expect(TextTransform.base64Encode.apply(to: "hello") == "aGVsbG8=")
        let text = "héllo ✓ wörld"
        let encoded = TextTransform.base64Encode.apply(to: text)
        #expect(TextTransform.base64Decode.apply(to: encoded) == text)
    }

    @Test("URL encode and decode")
    func whenURLEncoding_thenPercentEscapes() {
        #expect(TextTransform.urlEncode.apply(to: "a b&c=d") == "a%20b&c=d")
        #expect(TextTransform.urlDecode.apply(to: "a%20b%2Fc") == "a b/c")
    }

    @Test("tracking parameters are removed and real ones kept")
    func whenTrackingParams_thenOnlyTheRealQueryRemains() {
        let url = "https://example.com/p?utm_source=news&id=7&fbclid=abc"
        #expect(TextTransform.removeTrackingParams.apply(to: url) == "https://example.com/p?id=7")
    }

    @Test("a URL with only tracking parameters loses its query entirely")
    func whenOnlyTracking_thenNoQuery() {
        #expect(TextTransform.removeTrackingParams
            .apply(to: "https://example.com/p?utm_medium=x&gclid=1") == "https://example.com/p")
    }

    @Test("text that is not a URL passes through the tracking remover")
    func whenNotURL_thenUnchanged() {
        #expect(TextTransform.removeTrackingParams.apply(to: "hello world") == "hello world")
    }

    // MARK: Identifiers

    @Test("word cases", arguments: [
        (TextTransform.slugCase, "Hello, World! 2026", "hello-world-2026"),
        (.camelCase, "hello big_world", "helloBigWorld"),
        (.pascalCase, "hello big_world", "HelloBigWorld")
    ])
    func whenWordCase_thenExpected(transform: TextTransform, input: String, expected: String) {
        #expect(transform.apply(to: input) == expected)
    }

    // MARK: Hashes

    @Test("hashes match the published test vectors for \"abc\"")
    func whenHashed_thenKnownDigests() {
        #expect(TextTransform.sha256Hash
            .apply(to: "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(TextTransform.md5Hash.apply(to: "abc") == "900150983cd24fb0d6963f7d28e17f72")
    }

    // MARK: Markdown

    @Test("a URL becomes a Markdown link")
    func whenMarkdownLink_thenBracketed() {
        #expect(TextTransform.urlMarkdownLink.apply(to: "https://x.y/z") == "[https://x.y/z](https://x.y/z)")
    }

    @Test("code is fenced, with the language when it is known")
    func whenCodeBlock_thenFenced() {
        #expect(TextTransform.markdownCodeBlock.apply(to: "let a = 1") == "```\nlet a = 1\n```")
        #expect(TextTransform.markdownCodeBlock.apply(to: "let a = 1", language: "swift") == "```swift\nlet a = 1\n```")
        #expect(TextTransform.markdownCodeBlock.apply(to: "x", language: nil) == "```\nx\n```")
        #expect(TextTransform.markdownCodeBlock.apply(to: "x", language: "") == "```\nx\n```")
    }

    @Test("the language only affects the code fence")
    func whenLanguageGivenToOtherTransform_thenIgnored() {
        #expect(TextTransform.uppercase.apply(to: "abc", language: "swift") == "ABC")
    }

    // MARK: Every case

    @Test("every transform survives an empty string", arguments: TextTransform.allCases)
    func whenEmpty_thenNoCrash(transform: TextTransform) {
        _ = transform.apply(to: "")
    }

    @Test("every transform has an icon and a unique menu title")
    func whenListed_thenMenuEntriesAreDistinct() {
        #expect(TextTransform.allCases.allSatisfy { !$0.symbolName.isEmpty })
        #expect(Set(TextTransform.allCases.map(\.rawValue)).count == TextTransform.allCases.count)
    }

    @Test("Paste as… without tracking keeps a branch in the link and keeps an encoded plus")
    func removeTrackingParams_keepsRefAndEncodedPlus() {
        let link = "https://github.com/o/r/blob/x/f.swift?ref=main&utm_source=news&q=a%2Bb"

        #expect(
            TextTransform.removeTrackingParams.apply(to: link)
                == "https://github.com/o/r/blob/x/f.swift?ref=main&q=a%2Bb"
        )
    }

    @Test("minified JSON keeps slashes and gives the same key order every time")
    func jsonMinify_keepsSlashesAndSortsKeys() {
        let result = TextTransform.jsonMinify.apply(to: #"{"b":"https://x.com/a","a":1}"#)

        #expect(result == #"{"a":1,"b":"https://x.com/a"}"#)
    }
}
