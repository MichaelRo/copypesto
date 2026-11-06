// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("The Snippets pane leads with the person's snippets")
struct SnippetsPaneOrderTests {
    private static let sections = [
        "Text(\"Your snippets\")",
        "Text(\"Starters\")",
        "Text(\"From your clips\")",
        "Text(\"Placeholders you can use\")",
        "Text(\"Remember fill-in values\")",
        "Text(\"Suggestion statistics\")"
    ]

    private func source() throws -> String {
        try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Settings/SnippetsView.swift"),
            encoding: .utf8
        )
    }

    @Test("the sections come in the agreed order and every one is still there")
    func sectionsAreInOrder() throws {
        let text = try source()
        var previous = text.startIndex
        for marker in Self.sections {
            let found = text.range(of: marker, range: previous..<text.endIndex)
            #expect(found != nil, "\(marker) is missing or out of order")
            if let found { previous = found.upperBound }
        }
    }

    @Test("the placeholder reference is shown, not folded, keeps its VoiceOver label and links to the guide")
    func placeholdersAreShown() throws {
        let text = try source()
        #expect(!text.contains("DisclosureGroup"))
        #expect(!text.contains("placeholdersOpen"))
        #expect(text.contains("Placeholders you can use in a snippet"))
        #expect(text.contains("Filled in when you paste."))
        #expect(text.contains("See the guide"))
        #expect(text.contains("https://copypesto.net/docs/settings/#snippets"))
    }
}
