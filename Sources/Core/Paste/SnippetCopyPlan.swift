// SPDX-License-Identifier: MIT
import Foundation

/// What copying a snippet needs from the person where there is no target app to read from (the iPhone and iPad
/// library, ADR 0017): the fields to ask for, whether `{{clipboard}}` or `{{selection}}` will be filled from what the
/// person enters in the sheet, and the placeholders that have nothing to read and come out empty.
public struct SnippetCopyPlan: Equatable, Sendable {
    public let fields: [SnippetField]
    public let usesClipboard: Bool
    public let usesSelection: Bool
    public let leftEmpty: [String]

    /// Nil when the text is not a snippet or has no placeholder.
    public static func plan(for text: String, isSnippet: Bool) -> SnippetCopyPlan? {
        guard isSnippet else { return nil }
        let normalized = FillInParser.convertingAllVariables(in: text)
        guard TemplateExpander.containsPlaceholders(normalized) else { return nil }
        return SnippetCopyPlan(
            fields: FillInParser.fields(in: normalized),
            usesClipboard: TemplateExpander.referencesClipboard(in: normalized),
            usesSelection: TemplateExpander.referencesSelection(in: normalized),
            leftEmpty: normalized.contains("{{app}}") ? ["app"] : []
        )
    }

    /// A sheet is needed when the person fills a field, provides selected text, or pastes the clipboard in; a snippet
    /// of
    /// dates, times and IDs copies at once.
    public var needsSheet: Bool {
        !fields.isEmpty || usesClipboard || usesSelection
    }

    /// The text to copy: the fields and automatic placeholders filled, `{{clipboard}}` and `{{selection}}` with what
    /// was
    /// entered in the sheet (never a silent read of the clipboard), and no app name.
    public func expanded(
        _ text: String, fills: SnippetFills, pastedClipboard: String, selectedText: String = "", at date: Date = .now
    )
        -> String
    {
        let normalized = FillInParser.convertingAllVariables(in: text)
        return TemplateExpander.expansionWithCaret(
            of: normalized, isSnippet: true, at: date, fills: fills, targetApp: "",
            clipboardProvider: { pastedClipboard }, selectionProvider: { selectedText }
        )?.text ?? text
    }
}
