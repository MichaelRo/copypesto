// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Snippet drafts")
struct SnippetDraftTests {
    @Test("text with no placeholder is not a snippet yet, because it would be saved and never listed")
    func whenNoPlaceholder_thenNeedsOne() {
        #expect(SnippetDraft.evaluate("Best regards") == .needsPlaceholder)
        #expect(SnippetDraft.evaluate("   \n ") == .empty)
        #expect(SnippetDraft.evaluate("Hello {{cursor}}") == .ready)
    }

    @Test("every placeholder the sheet offers is one the expander fills in")
    func whenOffered_thenExpandable() {
        for placeholder in SnippetDraft.placeholders {
            let expanded = TemplateExpander.expand("x \(placeholder.token) y", clipboardProvider: { "copied" })
            #expect(!expanded.contains("{{"), "\(placeholder.token) is offered but not expanded")
        }
    }

    @Test("every starter is a snippet, with its own id and name")
    func whenStarters_thenAllAreSnippets() {
        let starters = SnippetStarters.all

        #expect(starters.allSatisfy { SnippetDraft.evaluate($0.text) == .ready })
        #expect(Set(starters.map(\.id)).count == starters.count)
        #expect(Set(starters.map(\.name)).count == starters.count)
        #expect(starters.allSatisfy { $0.blurb.hasSuffix(".") })
    }

    @Test("inserting a placeholder places it at the caret or replaces the selection and advances the caret")
    func whenInsertingPlaceholderAtCaretOrSelection_thenInsertsInPlace() {
        let mid = SnippetDraft.inserting("{{date}}", into: "Hello world", at: NSRange(location: 6, length: 0))
        #expect(mid.text == "Hello {{date}}world")
        #expect(mid.cursorLocation == 14)

        let replaced = SnippetDraft.inserting("{{clipboard}}", into: "Hello world", at: NSRange(location: 6, length: 5))
        #expect(replaced.text == "Hello {{clipboard}}")
        #expect(replaced.cursorLocation == 19)
    }
}

@Suite("Snippets worth suggesting")
struct SnippetSuggesterTests {
    private func candidate(
        _ text: String = "Thanks for reaching out, I will reply tomorrow.", pastes: Int = 5, pinned: Bool = false,
        textual: Bool = true, secret: Bool = false
    )
    -> SnippetCandidate {
        SnippetCandidate(
            id: UUID(), text: text, pasteCount: pastes, isPinned: pinned, isTextual: textual, isSecret: secret
        )
    }

    @Test("text pasted often enough is suggested, the most pasted first, at most three")
    func whenPastedOften_thenSuggestedMostFirst() {
        let list = [candidate(pastes: 3), candidate(pastes: 9), candidate(pastes: 5), candidate(pastes: 4)]

        let picked = SnippetSuggester.suggestions(from: list)

        #expect(picked.map(\.pasteCount) == [9, 5, 4])
    }

    @Test("a clip pasted once or twice, a pinned one, a picture and a secret are never suggested")
    func whenNotSuitable_thenLeftOut() {
        let list = [
            candidate(pastes: 2), candidate(pinned: true), candidate(textual: false), candidate(secret: true),
            candidate("short"), candidate(String(repeating: "x", count: 2001))
        ]

        #expect(SnippetSuggester.suggestions(from: list).isEmpty)
    }

    @Test("a dismissed clip is not suggested again")
    func whenDismissed_thenLeftOut() {
        let kept = candidate()
        let dismissed = candidate()

        let picked = SnippetSuggester.suggestions(from: [kept, dismissed], dismissed: [dismissed.id])

        #expect(picked == [kept])
    }
}

@Suite("Reading a snippets file")
struct SnippetPackReaderTests {
    private func read(_ json: String) throws -> SnippetPack {
        try SnippetPackReader.read(Data(json.utf8))
    }

    @Test("Raycast's single braces become Pesto's double braces")
    func whenRaycastPlaceholders_thenConverted() throws {
        let pack = try read(#"[{"name":"Hello","text":"Hi {cursor}, today is {date} at {time}.","keyword":"hi"}]"#)

        #expect(pack.snippets == [ImportedSnippet(
            name: "Hello",
            text: "Hi {{cursor}}, today is {{date}} at {{time}}."
        )])
        #expect(pack.plainText.isEmpty)
    }

    @Test("text that already has double braces is not converted twice")
    func whenAlreadyPestoStyle_thenUnchanged() throws {
        let pack = try read(#"[{"name":"A","text":"{{date}} and {{cursor}}"}]"#)

        #expect(pack.snippets.first?.text == "{{date}} and {{cursor}}")
    }

    @Test("an entry with no placeholder is kept as plain text, not listed as a snippet")
    func whenNoPlaceholder_thenPlainText() throws {
        let pack = try read(#"[{"name":"Sign-off","text":"Best regards, Michael"}]"#)

        #expect(pack.snippets.isEmpty)
        #expect(pack.plainText == [ImportedSnippet(name: "Sign-off", text: "Best regards, Michael")])
    }

    @Test("tokens Pesto does not fill in are counted and left as typed")
    func whenUnsupportedToken_thenCountedAndKept() throws {
        let pack =
            try read(#"[{"name":"P","text":"Re: {selection} on {date}"},{"name":"Q","text":"{date format=\"yyyy\"}"}]"#)

        #expect(pack.withUnsupportedTokens == 2)
        #expect(pack.snippets.first?.text == "Re: {selection} on {{date}}")
    }

    @Test("Raycast's clipboard and uuid placeholders are converted, because Pesto fills them in")
    func whenClipboardOrUUID_thenConverted() throws {
        let pack = try read(#"[{"name":"R","text":"Re: {clipboard} id {uuid}"}]"#)

        #expect(pack.withUnsupportedTokens == 0)
        #expect(pack.snippets.first?.text == "Re: {{clipboard}} id {{uuid}}")
    }

    @Test("empty and oversized entries are skipped and counted")
    func whenEntriesAreUnusable_thenSkipped() throws {
        let huge = String(repeating: "a", count: SnippetPackReader.maxTextLength + 1)
        let pack = try read(#"[{"name":"E","text":"  "},{"name":"H","text":"\#(huge)"},{"name":"O","text":"{date}"}]"#)

        #expect(pack.skipped == 2)
        #expect(pack.snippets.count == 1)
    }

    @Test("a file with a snippets key, or something else entirely, is handled")
    func whenWrappedOrWrong_thenReadOrRefused() throws {
        #expect(try read(#"{"snippets":[{"name":"A","text":"{date}"}]}"#).snippets.count == 1)
        #expect(throws: SnippetPackReader.ReadError.notASnippetFile) { try read("not json") }
        #expect(throws: SnippetPackReader.ReadError.notASnippetFile) { try read(#"{"a":1}"#) }
        #expect(throws: SnippetPackReader.ReadError.tooLarge) {
            try SnippetPackReader.read(Data(count: SnippetPackReader.maxBytes + 1))
        }
    }

    @Test("a long list is cut at the limit, and the rest is counted as skipped")
    func whenTooManyEntries_thenCut() throws {
        let entries = (0..<(SnippetPackReader.maxEntries + 5)).map { _ in #"{"text":"{date}"}"# }.joined(separator: ",")

        let pack = try read("[\(entries)]")

        #expect(pack.snippets.count == SnippetPackReader.maxEntries)
        #expect(pack.skipped == 5)
    }
}
