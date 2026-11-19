// SPDX-License-Identifier: MIT
import Foundation

public extension QuickInsertEntry {
    /// The text AutoFill inserts: a snippet with its dates and IDs filled in now and its caret marker removed (the
    /// caret cannot be placed from an extension); anything else exactly as it was copied.
    func insertionText(at date: Date = .now) -> String {
        guard expandsOnInsert else { return text }
        return TemplateExpander.expansion(of: text, isSnippet: true, at: date, clipboardProvider: { "" }) ?? text
    }

    /// The line a picker shows: a snippet's title filled in as it would insert now, so `Thanks, {{date}}` reads as the
    /// date it gives; a title the person wrote has no placeholders and stands as it is.
    func label(at date: Date = .now) -> String {
        guard expandsOnInsert else { return title }
        return TemplateExpander.expansion(of: title, isSnippet: true, at: date, clipboardProvider: { "" }) ?? title
    }
}
