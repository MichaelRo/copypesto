// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("SnippetPreview: what a snippet will paste, and where the caret lands")
struct SnippetPreviewTests {
    private let date = Date(timeIntervalSinceReferenceDate: 9_000_000)

    @Test("the caret sits between what comes before {{cursor}} and what follows it")
    func whenCursor_thenSplitAtIt() {
        let preview = SnippetPreview.make(from: "Hi {{cursor}},\nBye", at: date)

        #expect(preview.before == "Hi ")
        #expect(preview.after == ",\nBye")
        #expect(preview.hasCaret)
    }

    @Test("without {{cursor}} the caret is at the end, and the whole text is before it")
    func whenNoCursor_thenCaretAtTheEnd() {
        let preview = SnippetPreview.make(from: "Thanks, {{date}}", at: date)

        #expect(!preview.hasCaret)
        #expect(preview.after.isEmpty)
        #expect(!preview.before.contains("{{"))
    }

    @Test("only the first {{cursor}} counts, and the others are dropped")
    func whenSeveralCursors_thenFirstCounts() {
        let preview = SnippetPreview.make(from: "A{{cursor}}B{{cursor}}C", at: date)

        #expect(preview.before == "A")
        #expect(preview.after == "BC")
    }

    @Test("dates are filled in before the caret is placed")
    func whenDateBeforeCursor_thenFilled() {
        let preview = SnippetPreview.make(from: "{{date}}: {{cursor}}!", at: date)

        #expect(preview.before.hasSuffix(": "))
        #expect(preview.after == "!")
        #expect(!preview.before.contains("{{"))
    }

    @Test("a placeholder Pesto does not know is left as typed")
    func whenUnknownPlaceholder_thenUntouched() {
        #expect(SnippetPreview.make(from: "Dear {{name}}", at: date).before == "Dear {{name}}")
    }
}
