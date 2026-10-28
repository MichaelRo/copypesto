// SPDX-License-Identifier: MIT
import PestoCore

@MainActor
extension AppState {
    /// The stack's items with its snippets filled in, asked once up front. Nil when the person cancels the prompt.
    func expandedStackItems(_ items: [PasteStack.Item], isSnippet: [Bool]) async -> [PasteStack.Item]? {
        let fields = PasteStack.fields(of: items, isSnippet: isSnippet)
        guard isSnippet.contains(true) else { return items }
        var fills = SnippetFills.initial(for: fields)
        if !fields.isEmpty {
            let title = String(localized: "Paste One by One")
            guard let asked = await askFillIns?(title, fields, fills) else { return nil }
            fills = asked
        }
        let app = pasteCoordinator.focusRestoration.targetName
        let clipboard = TemplateExpander.liveClipboardText()
        return zip(items, isSnippet).map { item, snippet in
            snippet ? item.expandingSnippet(fills: fills, targetApp: app, clipboard: clipboard) : item
        }
    }
}
