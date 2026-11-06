// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import Testing
@testable import PestoCore

@MainActor
@Suite("RTF and RTFD to GitHub-Flavored Markdown")
struct RTFMarkdownTests {
    private let body = NSFont.systemFont(ofSize: 13)
    private var bold: NSFont {
        NSFontManager.shared.convert(body, toHaveTrait: .boldFontMask)
    }

    private var italic: NSFont {
        NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
    }

    private var mono: NSFont {
        NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    private func run(_ text: String, _ attributes: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        var all = attributes
        if all[.font] == nil { all[.font] = body }
        return NSAttributedString(string: text, attributes: all)
    }

    private func rtf(_ document: NSAttributedString) throws -> Data {
        try document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private func markdown(_ document: NSAttributedString) throws -> String? {
        try RTFMarkdown.convert(rtf(document))
    }

    private func joined(_ parts: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        parts.forEach { result.append($0) }
        return result
    }

    private func listStyle(_ format: NSTextList.MarkerFormat, depth: Int = 1) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.textLists = (0..<depth).map { _ in NSTextList(markerFormat: format, options: 0) }
        return style
    }

    @Test("bold, italic, strikethrough, a link and code survive a trip through RTF")
    func whenRuns_thenInlineMarkdown() throws {
        let document = try joined([
            run("A "), run("bold", [.font: bold]), run(", "), run("italic", [.font: italic]), run(", "),
            run("gone", [.strikethroughStyle: 1]), run(" and a "),
            run("link", [.link: #require(URL(string: "https://example.com/a"))]), run(" and "), run(
                "code()",
                [.font: mono]
            ),
            run(".\n")
        ])
        #expect(try markdown(document) ==
            "A **bold**, *italic*, ~~gone~~ and a [link](https://example.com/a) and `code()`.")
    }

    @Test("neighbouring runs with the same style are one emphasis, and spaces stay outside the markers")
    func whenRunsRepeat_thenOneSpan() throws {
        let document = joined([
            run("one", [.font: bold, .foregroundColor: NSColor.red]), run(" two ", [.font: bold]), run("x\n")
        ])
        #expect(try markdown(document) == "**one two** x")
    }

    @Test("Markdown characters in the text are escaped")
    func whenSpecialCharacters_thenEscaped() throws {
        let document = joined([run("2 * 3 [x]\n"), run("# no\n"), run("b", [.font: bold]), run("\n")])
        #expect(try markdown(document) == "2 \\* 3 \\[x\\]\n\n\\# no\n\n**b**")
    }

    @Test("bulleted and numbered lists, with their numbers counting up")
    func whenLists_thenMarkdownLists() throws {
        let bullets = listStyle(.disc)
        let numbers = listStyle(.decimal)
        let document = joined([
            run("Intro\n"),
            run("one\n", [.paragraphStyle: bullets]), run("two\n", [.paragraphStyle: bullets]),
            run("Between\n"),
            run("first\n", [.paragraphStyle: numbers]), run("second\n", [.paragraphStyle: numbers])
        ])
        #expect(try markdown(document) == "Intro\n\n- one\n- two\n\nBetween\n\n1. first\n2. second")
    }

    @Test("a list inside a list is indented by its parent's marker")
    func whenNestedList_thenIndented() throws {
        let document = joined([
            run("a\n", [.paragraphStyle: listStyle(.decimal)]),
            run("a.1\n", [.paragraphStyle: listStyle(.disc, depth: 2)]),
            run("a.2\n", [.paragraphStyle: listStyle(.disc, depth: 2)]),
            run("b\n", [.paragraphStyle: listStyle(.decimal)])
        ])
        #expect(try markdown(document) == "1. a\n   - a.1\n   - a.2\n2. b")
    }

    @Test("a table becomes pipes with its first row as the header, and a pipe in a cell is escaped")
    func whenTable_thenPipes() throws {
        let table = NSTextTable()
        table.numberOfColumns = 2
        func cell(_ row: Int, _ column: Int, _ text: String, _ font: NSFont? = nil) -> NSAttributedString {
            let block = NSTextTableBlock(
                table: table,
                startingRow: row,
                rowSpan: 1,
                startingColumn: column,
                columnSpan: 1
            )
            let style = NSMutableParagraphStyle()
            style.textBlocks = [block]
            return run(text + "\n", [.paragraphStyle: style, .font: font ?? body])
        }
        let document = joined([
            run("Before\n"),
            cell(0, 0, "Name"), cell(0, 1, "Note"),
            cell(1, 0, "Ana", bold), cell(1, 1, "a | b"),
            cell(2, 0, "Bo"), cell(2, 1, "x"),
            run("After\n")
        ])
        #expect(try markdown(document)
            == "Before\n\n| Name | Note |\n| --- | --- |\n| **Ana** | a \\| b |\n| Bo | x |\n\nAfter")
    }

    @Test("RTFD, the flat form with attachments, reads the same way")
    func whenRTFD_thenSame() throws {
        let document = joined([run("plain "), run("strong", [.font: bold]), run("\n")])
        let data = try #require(document.rtfd(from: NSRange(location: 0, length: document.length)))
        #expect(RTFMarkdown.convert(data, isRTFD: true) == "plain **strong**")
    }

    @Test("a document with no formatting is not a candidate, so the entry is not offered")
    func whenNothingFormatted_thenNil() throws {
        #expect(try markdown(run("just words\n\nmore words\n")) == nil)
        #expect(try markdown(run("")) == nil)
    }

    @Test("bytes that are not RTF, and RTF over the limit, are nil")
    func whenNotRTF_thenNil() {
        #expect(RTFMarkdown.convert(Data("<b>html</b>".utf8)) == nil)
        #expect(RTFMarkdown.convert(Data(repeating: 0x41, count: RTFMarkdown.maxInputBytes + 1)) == nil)
    }
}
