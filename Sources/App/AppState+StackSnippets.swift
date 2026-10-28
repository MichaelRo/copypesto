// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// A clip in a stack that may be a snippet: its id, and what was typed into it last time.
struct StackSnippetSource {
    let id: UUID
    let isSnippet: Bool
    let remembered: [String: String]
}

@MainActor
extension AppState {
    /// The stack's items with its snippets filled in, asked once up front, starting from what each snippet remembers
    /// and remembering the answers. Nil when the person cancels the prompt.
    func expandedStackItems(_ items: [PasteStack.Item], sources: [StackSnippetSource]) async -> [PasteStack.Item]? {
        let isSnippet = sources.map(\.isSnippet)
        let fields = PasteStack.fields(of: items, isSnippet: isSnippet)
        guard isSnippet.contains(true) else { return items }
        let remembers = AppDefaults.store.value(for: Setting.rememberFillIns)
        let remembered = remembers ? sources.reduce(into: [String: String]()) { $0.merge($1.remembered) { $1 } } : [:]
        var fills = SnippetFills.initial(for: fields, remembered: remembered)
        if !fields.isEmpty {
            let title = String(localized: "Paste One by One")
            guard let asked = await askFillIns?(title, fields, fills) else { return nil }
            fills = asked
            if remembers { rememberStackAnswers(fills, items: items, sources: sources) }
        }
        let app = pasteCoordinator.focusRestoration.targetName
        let clipboard = TemplateExpander.liveClipboardText()
        return zip(items, isSnippet).map { item, snippet in
            snippet ? item.expandingSnippet(fills: fills, targetApp: app, clipboard: clipboard) : item
        }
    }

    private func rememberStackAnswers(_ fills: SnippetFills, items: [PasteStack.Item], sources: [StackSnippetSource]) {
        for (item, source) in zip(items, sources) where source.isSnippet {
            guard case let .text(text) = item.payloadKind else { continue }
            let memory = FillInMemory.remembered(from: fills, fields: FillInParser.fields(in: text))
            guard !memory.isEmpty else { continue }
            let id = source.id
            Task { [weak self] in
                await self?.attempt("Couldn\u{2019}t remember what you typed") {
                    try await self?.storageService?.rememberFillIns(id: id, memory: memory)
                }
            }
        }
    }
}
