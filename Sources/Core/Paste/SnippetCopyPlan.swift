// SPDX-License-Identifier: MIT
import Foundation

/// What copying a snippet needs from the person where there is no target app to read from (the iPhone and iPad
/// library, ADR 0017): the fields to ask for, whether `{{clipboard}}` will be filled from what the person pastes into
/// the sheet, and the placeholders that have nothing to read and come out empty.
public struct SnippetCopyPlan: Equatable, Sendable {
    public let fields: [SnippetField]
    public let usesClipboard: Bool
    public let leftEmpty: [String]

    /// Nil when the text is not a snippet or has no placeholder.
    public static func plan(for text: String, isSnippet: Bool) -> SnippetCopyPlan? {
        guard isSnippet, TemplateExpander.containsPlaceholders(text) else { return nil }
        return SnippetCopyPlan(
            fields: FillInParser.fields(in: text),
            usesClipboard: TemplateExpander.referencesClipboard(in: text),
            leftEmpty: [
                TemplateExpander.referencesSelection(in: text) ? "selection" : nil,
                text.contains("{{app}}") ? "app" : nil
            ].compactMap(\.self)
        )
    }

    /// A sheet is needed when the person fills a field or pastes the clipboard in; a snippet of dates, times and IDs
    /// copies at once.
    public var needsSheet: Bool {
        !fields.isEmpty || usesClipboard
    }

    /// The text to copy: the fields and automatic placeholders filled, `{{clipboard}}` with what was pasted into the
    /// sheet (never a silent read of the clipboard), and no selection or app name.
    public func expanded(_ text: String, fills: SnippetFills, pastedClipboard: String, at date: Date = .now) -> String {
        TemplateExpander.expansionWithCaret(
            of: text, isSnippet: true, at: date, fills: fills, targetApp: "",
            clipboardProvider: { pastedClipboard }, selectionProvider: { "" }
        )?.text ?? text
    }
}
