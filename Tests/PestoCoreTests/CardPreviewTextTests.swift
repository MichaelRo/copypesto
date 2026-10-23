// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("CardPreviewText")
struct CardPreviewTextTests {
    @Test("a plain text is shown as it is")
    func whenPlain_thenUnchanged() {
        #expect(CardPreviewText.display("one\ntwo\n\nthree") == "one\ntwo\n\nthree")
    }

    @Test("every Unicode line break draws as a break", arguments: [
        "one\u{2028}two", "one\u{2029}two", "one\u{0B}two", "one\u{0C}two", "one\r\ntwo", "one\rtwo", "one\u{85}two"
    ])
    func whenAnyLineBreak_thenNewline(text: String) {
        #expect(CardPreviewText.display(text) == "one\ntwo")
    }

    @Test("blank lines and spaces at the start are dropped, and so is the indent of the first line")
    func whenLeadingBlank_thenDropped() {
        #expect(CardPreviewText.display("\n\n  \n   Header\nbody") == "Header\nbody")
        #expect(CardPreviewText.display("\t\u{2028}Header") == "Header")
    }

    @Test("whitespace at the end is dropped")
    func whenTrailingWhitespace_thenDropped() {
        #expect(CardPreviewText.display("body\n\n  \n") == "body")
        #expect(CardPreviewText.display("body   ") == "body")
    }

    @Test("a run of blank lines becomes one blank line, and a line of spaces counts as blank")
    func whenBlankRun_thenOne() {
        #expect(CardPreviewText.display("a\n\n\n\nb") == "a\n\nb")
        #expect(CardPreviewText.display("a\n \n\t\n  \nb") == "a\n\nb")
        #expect(CardPreviewText.display("a\n\nb") == "a\n\nb")
    }

    @Test("an indent after the first line is kept, because code needs it")
    func whenIndented_thenKept() {
        #expect(CardPreviewText.display("func f() {\n    return 1\n}") == "func f() {\n    return 1\n}")
    }

    @Test("a text of only whitespace has nothing to show")
    func whenOnlyWhitespace_thenEmpty() {
        #expect(CardPreviewText.display(" \n\t\n\u{2028} ").isEmpty)
        #expect(CardPreviewText.display("").isEmpty)
    }

    @Test("paragraphs are the runs of text between blank lines")
    func whenParagraphs_thenSplit() {
        #expect(CardPreviewText.paragraphs("a\nb\n\nc\n\n\n\nd") == ["a\nb", "c", "d"])
        #expect(CardPreviewText.paragraphs("single") == ["single"])
        #expect(CardPreviewText.paragraphs("  \n") == [])
    }

    @Test("a long hostile text is compacted in well under a frame")
    func whenAdversarial_thenFast() {
        let text = String(repeating: " \n\u{2028}\t", count: 125) + String(repeating: "a \n", count: 50)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = CardPreviewText.display(text) }
        #expect(elapsed < .milliseconds(16))
    }

    @Suite("the line count in the footer")
    struct LineCount {
        @Test("a clip with several lines shows its count when the whole text is in the preview")
        func whenWholeTextShown_thenCount() {
            #expect(CardPreviewText.footerLineCount(of: "a\nb\nc", textLength: 5) == 3)
        }

        @Test("one line shows no count")
        func whenSingleLine_thenNil() {
            #expect(CardPreviewText.footerLineCount(of: "just one line", textLength: 13) == nil)
        }

        @Test("a trailing break does not add a line")
        func whenTrailingBreak_thenNotCounted() {
            #expect(CardPreviewText.footerLineCount(of: "a\nb\n", textLength: 4) == 2)
        }

        @Test("a clip longer than its preview shows no count, because the preview's would be wrong")
        func whenCutShort_thenNil() {
            let preview = String(repeating: "x\n", count: 250)
            #expect(CardPreviewText.footerLineCount(of: preview, textLength: 501) == nil)
            #expect(CardPreviewText.footerLineCount(of: preview, textLength: 500) == 250)
        }

        @Test("a clip stored before the length was kept (0) is counted by what the preview holds when it is short")
        func whenLengthUnknown_thenOnlyAShortPreview() {
            #expect(CardPreviewText.footerLineCount(of: "a\nb", textLength: 0) == 2)
            let full = String(repeating: "x\n", count: 250)
            #expect(CardPreviewText.footerLineCount(of: full, textLength: 0) == nil)
        }
    }
}
