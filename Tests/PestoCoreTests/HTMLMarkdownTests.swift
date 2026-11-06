// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("HTML to GitHub-Flavored Markdown")
struct HTMLMarkdownTests {
    private func md(_ html: String) -> String? {
        HTMLMarkdown.convert(Data(html.utf8))
    }

    // MARK: Text and formatting

    @Test("headings, paragraphs and inline formatting")
    func whenFormattedText_thenMarkdown() {
        let html = "<h1>Title</h1>"
            + "<p>A <b>bold</b>, <i>italic</i>, <del>gone</del> and <code>code</code> line.</p><h3>Sub</h3>"
        #expect(md(html) == "# Title\n\nA **bold**, *italic*, ~~gone~~ and `code` line.\n\n### Sub")
    }

    @Test("spaces inside emphasis move outside the markers, and empty emphasis disappears")
    func whenEmphasisHasSpaces_thenMarkersHugTheWord() {
        #expect(md("<p>a<b> x </b>y <i> </i>z <strong></strong>w</p><p><b>keep</b></p>") == "a **x** y z w\n\n**keep**")
    }

    @Test("the same emphasis nested twice is written once")
    func whenEmphasisRepeats_thenOnce() {
        #expect(md("<p><b><strong>x</strong> <span style=\"font-weight:700\">y</span></b></p>") == "**x y**")
    }

    @Test("a heading is not also bold")
    func whenHeadingHasBold_thenPlainInHeading() {
        #expect(md("<h2><b>Big</b> <i>news</i></h2>") == "## Big *news*")
    }

    @Test("a line break inside a paragraph is a backslash break, and none is left at either end")
    func whenBr_thenBackslashBreak() {
        #expect(md("<p><br>one<br>two<br></p><p><b>x</b></p>") == "one\\\ntwo\n\n**x**")
    }

    @Test("Markdown characters in text are escaped, but not inside words")
    func whenSpecialCharacters_thenEscaped() {
        #expect(md("<p>2 * 3 = [six] snake_case _under_ a|b `tick` \\ &lt;tag> ~~x~~</p><b>.</b>")
            == "2 \\* 3 = \\[six\\] snake_case \\_under\\_ a|b \\`tick\\` \\\\ \\<tag> \\~\\~x\\~\\~\n\n**.**")
    }

    @Test("a line that would turn into a heading, quote, list or rule is escaped")
    func whenLineLooksLikeMarkdown_thenEscaped() {
        #expect(
            md("<p># not a heading</p><p>&gt; not a quote</p><p>- not a list</p><p>1. not a list</p><p>---</p><b>.</b>")
                == "\\# not a heading\n\n\\> not a quote\n\n\\- not a list\n\n1\\. not a list\n\n\\---\n\n**.**"
        )
    }

    @Test("entities and unicode are read as text")
    func whenEntities_thenCharacters() {
        #expect(md("<p>Fish &amp; chips &mdash; 値段 &#x1F355; caf&eacute;?</p><b>.</b>")
            == "Fish & chips \u{2014} 値段 🍕 caf&eacute;?\n\n**.**")
    }

    // MARK: Links and pictures

    @Test("links keep their text; unsafe addresses keep only the text")
    func whenLinks_thenOnlySafeOnesSurvive() {
        let html = "<p><a href=\"https://example.com/a b(c)\">site</a> <a href=\"/docs?x=1\">rel</a> "
            + "<a href=\"mailto:a@b.co\">mail</a> <a href=\"javascript:alert(1)\">js</a> "
            + "<a href=\"data:text/html,x\">data</a> <a href=\"file:///etc/passwd\">file</a> <a>none</a></p>"
        #expect(md(html) ==
            "[site](https://example.com/a%20b%28c%29) [rel](/docs?x=1) [mail](mailto:a@b.co) js data file none")
    }

    @Test("a link whose text is its address becomes an autolink, and an empty link vanishes")
    func whenLinkTextIsAddress_thenAutolink() {
        #expect(
            md("<p>See <a href=\"https://example.com\">https://example.com</a> now <a href=\"https://x.co\"></a>.</p>")
                == "See <https://example.com> now ."
        )
    }

    @Test("a link around bold text keeps both")
    func whenBoldLink_thenBoth() {
        #expect(md("<a href=\"https://example.com\"> <b>go</b> </a>") == "[**go**](https://example.com)")
    }

    @Test("a picture keeps its alt text and a web address; a data picture keeps the alt only")
    func whenImages_thenAltAndSafeSource() {
        let html = "<p><img src=\"https://example.com/a.png\" alt=\"A cat\"><img src=\"data:image/png;base64,AAAA\" alt=\"inline\"></p>"
        #expect(md(html) == "![A cat](https://example.com/a.png)inline")
    }

    // MARK: Lists, quotes and code

    @Test("nested lists keep their levels, and an ordered list its start")
    func whenNestedLists_thenIndented() {
        let html = "<ul><li>one<ul><li>one.a</li><li>one.b<ol start=\"3\"><li>deep</li></ol></li></ul></li>"
            + "<li>two</li></ul>"
        #expect(md(html) == "- one\n  - one.a\n  - one.b\n    3. deep\n- two")
    }

    @Test("an item with two paragraphs stays one item; ordered numbers count up")
    func whenItemHasParagraphs_thenContinuation() {
        let html = "<ol><li><p>First</p><p>more</p></li><li>Second</li><li></li></ol>"
        #expect(md(html) == "1. First\n\n   more\n2. Second")
    }

    @Test("items without end tags and a list inside a list (as Word writes it) are read")
    func whenSloppyLists_thenStillALift() {
        #expect(md("<ul><li>a<li>b<ul><li>c</ul></ul>") == "- a\n- b\n  - c")
        #expect(md("<ul><li>a</li><ul><li>b</li></ul></ul>") == "- a\n  - b")
    }

    @Test("a quote, a rule and a code block")
    func whenQuoteRuleCode_thenFenced() {
        let html = "<blockquote><p>quoted</p><p>twice</p></blockquote><hr><pre>"
            + "<code class=\"language-swift\">let a = 1 &lt; 2\n\nprint(a)\n</code></pre>"
        #expect(md(html) == "> quoted\n>\n> twice\n\n---\n\n```swift\nlet a = 1 < 2\n\nprint(a)\n```")
    }

    @Test("code containing backticks is fenced with more of them")
    func whenCodeHasBackticks_thenLongerFence() {
        #expect(md("<pre>a\n```\nb</pre><p>x <code>`tick`</code> <code>a``b</code></p>")
            == "````\na\n```\nb\n````\n\nx `` `tick` `` ```a``b```")
    }

    // MARK: Tables

    @Test("a table becomes pipes with its first row as the header; cells keep their formatting and escape pipes")
    func whenTable_thenPipes() {
        let html = "<table><thead><tr><th>Name</th><th>Note</th></tr></thead><tbody>"
            + "<tr><td><b>Ana</b></td><td>a | b</td></tr><tr><td><a href=\"https://x.co\">Bo</a></td><td></td></tr></tbody></table>"
        #expect(md(html) == "| Name | Note |\n| --- | --- |\n| **Ana** | a \\| b |\n| [Bo](https://x.co) |  |")
    }

    @Test("a table without header cells uses its first row; short rows are padded")
    func whenNoHeaderCellsAndRagged_thenPadded() {
        #expect(
            md("<table><tr><td>a</td><td>b</td><td>c</td></tr><tr><td>1</td></tr><tr><td>2</td><td>3</td></tr></table>")
                == "| a | b | c |\n| --- | --- | --- |\n| 1 |  |  |\n| 2 | 3 |  |"
        )
    }

    @Test("colspan and rowspan fill the cells they cover with empty ones")
    func whenSpans_thenEmptyCellsPadTheGrid() {
        let html = "<table><tr><th colspan=\"2\">Wide</th><th>C</th></tr><tr><td rowspan=\"2\">tall</td>"
            + "<td>b</td><td>c</td></tr><tr><td>b2</td><td>c2</td></tr></table>"
        #expect(md(html) == "| Wide |  | C |\n| --- | --- | --- |\n| tall | b | c |\n|  | b2 | c2 |")
    }

    @Test("a table inside a cell, and a list inside a cell, are flattened with line breaks")
    func whenNestedInCell_thenFlattened() {
        let html = "<table><tr><th>A</th><th>B</th></tr><tr>"
            + "<td><table><tr><td>x</td><td>y</td></tr><tr><td>z</td><td></td></tr></table></td>"
            + "<td><ul><li>one</li><li>two<ul><li>three</li></ul></li></ul></td></tr></table>"
        #expect(md(html) == "| A | B |\n| --- | --- |\n| x, y<br>z | \u{2022} one<br>\u{2022} two<br>\u{2022} three |")
    }

    @Test("two paragraphs and a line break in a cell use <br>")
    func whenBlocksInCell_thenBr() {
        #expect(
            md(
                "<table><tr><td>h1</td><td>h2</td></tr><tr><td><p>one</p><p>two<br>three</p></td><td>x</td>"
                    + "</tr></table>"
            )
                == "| h1 | h2 |\n| --- | --- |\n| one<br>two<br>three | x |"
        )
    }

    @Test("a table of one cell is layout, and its content is read as the page")
    func whenLayoutTable_thenTransparent() {
        #expect(md("<table><tr><td><h2>Hi</h2><p>Body <b>text</b></p></td></tr></table>") == "## Hi\n\nBody **text**")
    }

    @Test("a table with no cells, or too wide, writes nothing")
    func whenTableUnusable_thenNil() {
        #expect(md("<table></table><b></b>") == nil)
        let wide = "<table><tr>" + String(repeating: "<td>x</td>", count: HTMLMarkdown.maxColumns + 1) + "</tr>"
            + "<tr><td>y</td></tr></table>"
        #expect(md(wide) == nil)
        #expect(
            md(
                "<table><tr><td colspan=\"100\">a</td><td colspan=\"100\">b</td><td>c</td></tr><tr><td>1</td>"
                    + "</tr></table>"
            ) ==
                nil
        )
    }

    // MARK: Real-world sources

    @Test("Google Docs: the wrapper that says font-weight normal is not bold, its 700 spans are")
    func whenGoogleDocs_thenOnlyRealBold() {
        let html = "<meta charset='utf-8'><b style=\"font-weight:normal;\" id=\"docs-internal-guid-1\">"
            + "<p dir=\"ltr\"><span style=\"font-weight:700;\">Heading</span>"
            + "<span style=\"font-style:italic;\"> and </span>"
            + "<span style=\"font-weight:400;\">plain</span></p><ul><li dir=\"ltr\"><p><span>item</span></p>"
            + "</li></ul></b>"
        #expect(md(html) == "**Heading** *and* plain\n\n- item")
    }

    @Test("Word: conditional comments, o:p tags, and Mso classes read cleanly")
    func whenWord_thenCleanMarkdown() {
        let html = "<html xmlns:o=\"urn:schemas-microsoft-com:office:office\"><head>"
            + "<style>p.MsoNormal{margin:0}</style></head><body>"
            + "<!--[if gte mso 9]><xml><o:OfficeDocumentSettings/></xml><![endif]--><!--StartFragment-->"
            + "<p class=MsoNormal><b>Report</b><o:p></o:p></p><p class=MsoNormal>Total:&nbsp;<i>42</i>"
            + "<o:p>&nbsp;</o:p></p><!--EndFragment--></body></html>"
        #expect(md(html) == "**Report**\n\nTotal: *42*")
    }

    @Test("scripts, styles and hidden machinery are dropped")
    func whenScriptsAndStyles_thenGone() {
        #expect(
            md(
                "<style>b{color:red}</style><script>var a = '<b>x</b>'</script><p>ok <b>yes</b></p><svg>"
                    + "<text>no</text></svg><noscript>no</noscript>"
            )
                == "ok **yes**"
        )
    }

    @Test("a browser selection: spans, divs, a link around a div")
    func whenBrowserSelection_thenContainersAreTransparent() {
        let html = "<div class=\"card\"><a href=\"https://example.com/post\"><div><span class=\"t\">Title here</span></div></a>"
            + "<div><span style=\"color: rgb(0,0,0)\">Some </span><em>emphasis</em></div></div>"
        #expect(md(html) == "Title here\n\nSome *emphasis*")
    }

    // MARK: When there is nothing to write

    @Test("markup with no structure is not a candidate, so the entry is not offered", arguments: [
        "<span style=\"color:red\">hello</span>", "<div>plain</div><div>text</div>", "<p>just a paragraph</p>",
        "hello", "", "<b></b>", "<a href=\"javascript:x\">js</a>", "<meta charset='utf-8'>"
    ])
    func whenNoStructure_thenNil(html: String) {
        #expect(md(html) == nil)
    }

    // MARK: Bounds

    @Test("hostile nesting is refused, not recursed into")
    func whenTooDeep_thenNil() {
        #expect(md(String(repeating: "<div>", count: 5000) + "<b>x</b>") == nil)
        #expect(md(String(repeating: "<b>", count: 200) + "x") == nil)
        #expect(md(String(repeating: "<table><tr><td>", count: 100) + "x") == nil)
    }

    @Test("an unterminated tag or comment ends the reading and keeps what came before")
    func whenTruncated_thenWhatCameBefore() {
        #expect(md("<p><b>kept</b></p><p>cut <a href=\"https://x") == "**kept**\n\ncut")
        #expect(md("<p><b>kept</b></p><!-- never ends") == "**kept**")
    }

    @Test("input over the limit is refused without being read")
    func whenTooBig_thenNil() {
        #expect(md("<b>x</b>" + String(repeating: "a", count: HTMLMarkdown.maxInputBytes)) == nil)
    }

    @Test("markup at the size limit converts, and a debug build still does it in well under a second")
    func whenAtTheLimit_thenFast() throws {
        var html = "<h1>Report</h1><table><tr><th>Name</th><th>Link</th><th>N</th></tr>"
        let row = "<tr><td><b>Ana</b></td><td><a href=\"https://example.com/a?x=1\">link</a> &amp; text</td><td>12,345</td></tr>"
        while html.utf8.count < HTMLMarkdown.maxInputBytes / 2 {
            html += row
        }
        html += "</table><ul>"
        while html.utf8.count < HTMLMarkdown
            .maxInputBytes - 200
        {
            html += "<li>item <i>one</i> with <code>code</code></li>"
        }
        html += "</ul>"
        let start = ContinuousClock.now
        let out = try #require(md(html))
        let elapsed = ContinuousClock.now - start
        #expect(out.hasPrefix("# Report"))
        if ProcessInfo.processInfo.environment["CI"] == nil { #expect(elapsed < .milliseconds(400), "took \(elapsed)") }
    }
}
