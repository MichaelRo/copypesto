// SPDX-License-Identifier: MIT
import Foundation

public extension PasteStack {
    /// The fields every snippet text in a stack asks for, so the stack asks once, when it starts, and a plain ⌘V never
    /// waits for a person.
    static func fields(of items: [Item], isSnippet: [Bool]) -> [SnippetField] {
        FillInParser.fields(inAll: zip(items, isSnippet).compactMap { item, snippet in
            guard snippet else { return nil }
            switch item.payloadKind {
            case let .text(text), let .richText(text): return text
            case .nonText: return nil
            }
        })
    }
}

public extension PasteStack.Item {
    /// This item with a snippet's tokens filled in. Genuine rich-text styling is kept; code-block formatting is
    /// dropped.
    @MainActor
    func expandingSnippet(fills: SnippetFills, targetApp: String, clipboard: String) -> PasteStack.Item {
        let text: String
        switch payloadKind {
        case let .text(str), let .richText(str): text = str
        case .nonText: return self
        }
        guard let expanded = TemplateExpander.expansion(
            of: text, isSnippet: true, fills: fills, targetApp: targetApp, clipboardProvider: { clipboard }
        ) else { return self }
        let expandedRich = richPayload.flatMap {
            TemplateExpander.expandRichPayload(
                $0, fills: fills, targetApp: targetApp, clipboardProvider: { clipboard }
            )
        }
        return PasteStack.Item(
            previewText: previewText.contains("{{") ? expanded : previewText,
            payloadKind: expandedRich != nil ? .richText(expanded) : .text(expanded),
            pasteboardData: Data(expanded.utf8),
            pasteboardType: "public.utf8-plain-text",
            richPayload: expandedRich,
            isProtected: isProtected
        )
    }
}
