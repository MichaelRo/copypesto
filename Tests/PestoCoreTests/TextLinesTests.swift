// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("TextLines")
struct TextLinesTests {
    @Test("empty text has no lines to count and no extra ones")
    func whenEmpty_thenZero() {
        #expect(TextLines.count(in: "") == 0)
        #expect(TextLines.extra(in: "") == 0)
    }

    @Test("one line has none after the first")
    func whenSingleLine_thenNoExtra() {
        #expect(TextLines.count(in: "Standup") == 1)
        #expect(TextLines.extra(in: "Standup") == 0)
    }

    @Test("a single trailing line break does not add a line")
    func whenTrailingBreak_thenIgnored() {
        #expect(TextLines.count(in: "a\nb\n") == 2)
        #expect(TextLines.extra(in: "a\nb\n") == 1)
    }

    @Test("blank lines in the middle count")
    func whenBlankLines_thenCounted() {
        #expect(TextLines.count(in: "a\n\n\nb") == 4)
    }

    @Test("Windows line breaks and the Unicode line separator each count once")
    func whenOtherBreaks_thenOneLineEach() {
        #expect(TextLines.count(in: "a\r\nb\r\nc") == 3)
        #expect(TextLines.count(in: "a\u{2028}b") == 2)
    }

    @Test("only a line break is one empty line")
    func whenOnlyBreak_thenOneLine() {
        #expect(TextLines.count(in: "\n") == 1)
    }
}
