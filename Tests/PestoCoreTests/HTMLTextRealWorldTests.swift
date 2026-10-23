// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("HTML as real programs put it on the clipboard")
struct HTMLTextRealWorldTests {
    private func text(_ html: String) -> String {
        HTMLText.plainText(from: Data(html.utf8))
    }

    @Test("a Chrome fragment keeps its words and none of its fragment markers or styles")
    func whenChromeFragment_thenWordsOnly() {
        let html = """
        <meta charset='utf-8'><html><body><!--StartFragment--><span style="color: rgb(0, 0, 0);">Hello</span> \
        <a href="https://example.com/?a=1&amp;b=2">world</a><!--EndFragment--></body></html>
        """
        #expect(text(html) == "Hello world")
    }

    @Test("a table copied from a spreadsheet keeps its rows on separate lines and its cells apart")
    func whenTable_thenRowsAndCells() {
        let html = "<table><tr><td>Name</td><td>Qty</td></tr><tr><td>Basil</td><td>3</td></tr></table>"
        #expect(text(html) == "Name Qty\nBasil 3")
    }

    @Test("Word's namespaced tags and conditional comments leave only the text")
    func whenWordMarkup_thenText() {
        let html = "<p class=MsoNormal><o:p>&nbsp;</o:p>Dear Sam,<o:p></o:p></p>"
            + "<!--[if gte mso 9]><xml>x</xml><![endif]--><p>Thanks</p>"
        #expect(text(html) == "Dear Sam,\n\nThanks")
    }

    @Test("a script's own closing tag inside a string does not end the script early")
    func whenScriptHoldsAClosingLookalike_thenStillDropped() {
        #expect(text("<script>var s = '<\\/script>';</script>visible") == "visible")
    }

    @Test("unicode survives, and a numeric entity for an astral character decodes")
    func whenUnicode_thenKept() {
        #expect(text("<p>café ☕ &#x1F33F;</p>") == "café ☕ 🌿")
    }
}
