// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("SnippetRowText")
struct SnippetRowTextTests {
    @Test("a snippet without a title is named by its first line, and the body starts after it")
    func whenNoTitle_thenFirstLineIsNotRepeated() {
        let row = SnippetRowText(preview: "Hi {{name}},\nthanks for today.\nBest", customTitle: nil)

        #expect(row.title == "Hi {{name}},")
        #expect(row.body == "thanks for today.\nBest")
    }

    @Test("a one-line snippet is its own title and has no body to repeat it")
    func whenOneLine_thenNoBody() {
        let row = SnippetRowText(preview: "Hello {{name}}", customTitle: nil)

        #expect(row.title == "Hello {{name}}")
        #expect(row.body.isEmpty)
    }

    @Test("a title the person chose leaves the whole text in the body")
    func whenCustomTitle_thenBodyIsAll() {
        let row = SnippetRowText(preview: "Hi\nthere", customTitle: "Greeting")

        #expect(row.title == "Greeting")
        #expect(row.body == "Hi\nthere")
    }

    @Test("a first line too long for the title stays whole in the body")
    func whenFirstLineIsLong_thenNothingIsLost() {
        let long = String(repeating: "word ", count: 20)
        let row = SnippetRowText(preview: long + "\nsecond", customTitle: nil)

        #expect(row.title.count == SnippetRowText.titleLimit)
        #expect(row.body == long + "\nsecond")
    }

    @Test("blank lines before the first line and after it are skipped, as the title always did")
    func whenBlankLines_thenSkipped() {
        let row = SnippetRowText(preview: "\n\nFirst\n\nSecond", customTitle: nil)

        #expect(row.title == "First")
        #expect(row.body == "Second")
    }
}
