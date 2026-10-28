// SPDX-License-Identifier: MIT
import Foundation

public extension PasteStack {
    /// The fields every snippet text in a stack asks for, so the stack asks once, when it starts, and a plain ⌘V never
    /// waits for a person.
    static func fields(of items: [Item], isSnippet: [Bool]) -> [SnippetField] {
        FillInParser.fields(inAll: zip(items, isSnippet).compactMap { item, snippet in
            guard snippet, case let .text(text) = item.payloadKind else { return nil }
            return text
        })
    }
}

public extension PasteStack.Item {
    /// This item with a snippet's tokens filled in. Formatting is dropped because the text under it changed.
    func expandingSnippet(fills: SnippetFills, targetApp: String, clipboard: String) -> PasteStack.Item {
        guard case let .text(text) = payloadKind,
              let expanded = TemplateExpander.expansion(
                  of: text, isSnippet: true, fills: fills, targetApp: targetApp, clipboardProvider: { clipboard }
              ) else { return self }
        return PasteStack.Item(
            previewText: previewText.contains("{{") ? expanded : previewText,
            payloadKind: .text(expanded),
            pasteboardData: Data(expanded.utf8),
            pasteboardType: pasteboardType,
            richPayload: nil,
            isProtected: isProtected
        )
    }
}
