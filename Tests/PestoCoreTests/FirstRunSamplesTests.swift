// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("First-run sample clips")
struct FirstRunSamplesTests {
    private func text(_ record: PasteImportRecord) throws -> String {
        let representation = try #require(record.representations.first)
        let data = try #require(Data(base64Encoded: representation.dataBase64))
        return try #require(String(bytes: data, encoding: .utf8))
    }

    @Test("a new install gets a welcome note and a sample snippet without creating a Snippets collection")
    func whenRecordsBuilt_thenWelcomeAndSnippet() {
        let records = FirstRunSamples.records(shortcut: "⌘⇧V")

        #expect(records.count == 2)
        #expect(records[0].title == FirstRunSamples.welcomeTitle)
        #expect(records[0].pinboard == nil)
        #expect(records[1].title == FirstRunSamples.snippetTitle)
        #expect(records[1].pinboard == nil)
        #expect(records[0].timestamp > records[1].timestamp, "the welcome note is the newest clip")
    }

    @Test("the welcome note names the user's real shortcut, not a fixed one")
    func whenShortcutCustomised_thenWelcomeUsesIt() throws {
        let first = try #require(FirstRunSamples.records(shortcut: "⌃⌥P").first)
        let welcome = try text(first)

        #expect(welcome.contains("⌃⌥P opens this shelf"))
        #expect(!welcome.contains("⌘⇧V"))
    }

    @Test("the snippet is a real template: every token is one the expander fills in")
    func whenSnippetExpanded_thenNoTokensRemain() throws {
        let last = try #require(FirstRunSamples.records(shortcut: "x").last)
        let snippet = try text(last)

        #expect(TemplateExpander.containsPlaceholders(snippet))
        #expect(!TemplateExpander.expand(snippet).contains("{{"))
    }

    @Test("the samples follow the copy guide: no banned vocabulary and no Hebrew")
    func whenCopyRead_thenGlossaryRespected() throws {
        let all = try FirstRunSamples.records(shortcut: "x").map(text).joined(separator: "\n")

        for banned in ["NSFW", "pinboard", "overlay", "item"] {
            #expect(!all.localizedCaseInsensitiveContains(banned), "\(banned) is not in the glossary")
        }
        #expect(all.unicodeScalars.allSatisfy { !(0x0590...0x05FF).contains($0.value) })
    }
}
