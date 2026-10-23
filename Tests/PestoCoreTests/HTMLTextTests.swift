// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The plain text of copied HTML")
struct HTMLTextTests {
    private func text(_ html: String) -> String {
        HTMLText.plainText(from: Data(html.utf8))
    }

    @Test("paragraphs and line breaks become lines; other tags vanish")
    func whenBlocks_thenLines() {
        #expect(text("<p>First <b>bold</b> line</p><p>Second<br>third</p>") == "First bold line\n\nSecond\nthird")
        #expect(text("<ul><li>one</li><li>two</li></ul>") == "one\ntwo")
    }

    @Test("script, style, head and comments never appear in the text")
    func whenNonContent_thenDropped() {
        let html = """
        <html><head><title>Title</title><style>p { color: red }</style></head>
        <body><!-- a comment --><script>alert("x")</script><p>Visible</p><STYLE>x{}</STYLE></body></html>
        """
        #expect(text(html) == "Visible")
    }

    @Test("entities are decoded: named, decimal and hexadecimal", arguments: [
        ("a &amp; b", "a & b"), ("&lt;tag&gt;", "<tag>"), ("&quot;q&quot; &apos;s&apos;", "\"q\" 's'"),
        ("&#65;&#x42;", "AB"), ("5&nbsp;km", "5 km"), ("a&mdash;b", "a\u{2014}b"), ("&hellip;", "\u{2026}"),
        ("&unknown;", "&unknown;"), ("AT&T", "AT&T"), ("&#xZZ;", "&#xZZ;")
    ])
    func whenEntity_thenDecoded(input: String, expected: String) {
        #expect(text(input) == expected)
    }

    @Test("whitespace runs collapse and the ends are trimmed")
    func whenWhitespace_thenCollapsed() {
        #expect(text("  <div>  a \n\n  b\t c  </div>  ") == "a b c")
    }

    @Test("a stray less-than sign is text, and a broken tag cannot swallow earlier text")
    func whenMalformed_thenNothingEarlierIsLost() {
        #expect(text("1 < 2 and 3 > 2") == "1 < 2 and 3 > 2")
        #expect(text("kept<p unfinished") == "kept")
        #expect(text("kept<script>never closed") == "kept")
        #expect(text("<a href=\"x>y\">link</a>") == "link")
    }

    @Test("images, links and stylesheets contribute no text")
    func whenReferences_thenNoText() {
        #expect(
            text("<img src=\"http://127.0.0.1:9/a.png\"><link rel=stylesheet href=\"http://127.0.0.1:9/a.css\">hi") ==
                "hi"
        )
    }

    @Test(
        "a megabyte of angle brackets is handled in linear time",
        .enabled(if: !HostedRunner.isActive, "a wall-clock budget is only meaningful on a developer Mac")
    )
    func whenAdversarial_thenFast() {
        let hostile = Data(String(repeating: "<a ", count: 350_000).utf8)
        let nested = Data(String(repeating: "<p><", count: 250_000).utf8)
        let start = ContinuousClock.now
        _ = HTMLText.plainText(from: hostile)
        _ = HTMLText.plainText(from: nested)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test("bytes that are not UTF-8 do not crash")
    func whenInvalidUTF8_thenStillText() {
        #expect(HTMLText.plainText(from: Data([0x3C, 0x70, 0x3E, 0xFF, 0xFE, 0x68, 0x69])).contains("hi"))
    }
}
