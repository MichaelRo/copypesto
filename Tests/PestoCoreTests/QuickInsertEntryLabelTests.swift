// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("A quick-insert entry's label")
struct QuickInsertEntryLabelTests {
    private let noon = Date(timeIntervalSince1970: 1_795_000_000)

    private func entry(title: String, expands: Bool) -> QuickInsertEntry {
        QuickInsertEntry(
            id: UUID(),
            section: .snippets,
            kind: .text,
            title: title,
            text: title,
            expandsOnInsert: expands
        )
    }

    @Test("a snippet's label reads as it would insert now: its dates filled in, its caret marker gone")
    func whenASnippet_thenItsLabelIsExpanded() {
        let label = entry(title: "Thanks, {{date}}{{cursor}}", expands: true).label(at: noon)
        let date = TemplateExpander.expansion(of: "{{date}}", isSnippet: true, at: noon, clipboardProvider: { "" })
        #expect(label == "Thanks, " + (date ?? ""))
    }

    @Test("a title the person gave, or a clip that is not a snippet, is shown as it is")
    func whenNotExpanding_thenTheTitleStands() {
        #expect(entry(title: "Reply to Ana", expands: true).label(at: noon) == "Reply to Ana")
        #expect(entry(title: "helm {{ .Values }}", expands: false).label(at: noon) == "helm {{ .Values }}")
    }
}
