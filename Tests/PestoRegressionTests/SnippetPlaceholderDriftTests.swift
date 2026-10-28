// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Snippet placeholders: the editor's chips and every document that lists them say the same")
struct SnippetPlaceholderDriftTests {
    private static let documents = [
        "docs/guide/settings.md",
        "docs/design/snippets-and-suggestions.md",
        "docs/feature-reference.md"
    ]

    /// A chip carries one example offset (`{{date+1d}}`); the documents name the family, and the minus form with it.
    private static var documented: [String] {
        SnippetDraft.placeholders.flatMap { placeholder -> [String] in
            guard placeholder.token == "{{date+1d}}" else { return [placeholder.token] }
            return ["{{date+Nd}}", "{{date-Nd}}"]
        }
    }

    @Test("every placeholder the editor offers is named in the guide, the design note and the feature reference")
    func everyPlaceholderIsDocumented() throws {
        for document in Self.documents {
            let text = try String(
                contentsOf: SourceTree.repositoryRoot.appendingPathComponent(document), encoding: .utf8
            )
            let missing = Self.documented.filter { !text.contains("`\($0)`") }
            #expect(missing.isEmpty, "\(document) does not name: \(missing)")
        }
    }

    @Test("the editor offers the placeholders the expander documents")
    func expanderListsTheSameTokens() throws {
        let source = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Core/Paste/TemplateExpander.swift"),
            encoding: .utf8
        )
        let missing = Self.documented.filter { !source.contains($0) }
        #expect(missing.isEmpty, "TemplateExpander's header does not list: \(missing)")
    }

    @Test("the guide gives every placeholder an example result")
    func guideGivesExamples() throws {
        let guide = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("docs/guide/settings.md"), encoding: .utf8
        )
        let rows = guide.split(separator: "\n").filter { $0.hasPrefix("| `{{") }
        #expect(rows.count == Self.documented.count)
        for row in rows {
            let cells = row.split(separator: "|", omittingEmptySubsequences: true)
            #expect(cells.count == 3, "\(row) needs a token, a meaning and an example")
        }
    }
}
