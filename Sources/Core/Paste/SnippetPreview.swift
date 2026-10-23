// SPDX-License-Identifier: MIT
import Foundation

/// What the snippet editor shows under the text: the snippet as it will paste, split where the caret will land
/// (`{{cursor}}`), so a person sees the placeholders filled in and the caret before they save.
public struct SnippetPreview: Equatable, Sendable {
    public let before: String
    public let after: String
    public let hasCaret: Bool

    public static func make(
        from template: String,
        at date: Date = .now,
        clipboardProvider: () -> String = TemplateExpander.liveClipboardText
    )
    -> SnippetPreview {
        guard let expanded = TemplateExpander.expansionWithCaret(
            of: template, isSnippet: true, at: date, clipboardProvider: clipboardProvider
        ) else {
            return SnippetPreview(before: template, after: "", hasCaret: false)
        }
        guard let afterCount = expanded.charactersAfterCursor else {
            return SnippetPreview(before: expanded.text, after: "", hasCaret: false)
        }
        let cut = expanded.text.index(expanded.text.endIndex, offsetBy: -afterCount)
        return SnippetPreview(
            before: String(expanded.text[..<cut]), after: String(expanded.text[cut...]), hasCaret: true
        )
    }
}
