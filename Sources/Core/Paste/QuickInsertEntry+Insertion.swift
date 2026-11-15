// SPDX-License-Identifier: MIT
import Foundation

public extension QuickInsertEntry {
    /// The text AutoFill inserts: a snippet with its dates and IDs filled in now and its caret marker removed (the
    /// caret cannot be placed from an extension); anything else exactly as it was copied.
    func insertionText(at date: Date = .now) -> String {
        guard expandsOnInsert else { return text }
        return TemplateExpander.expansion(of: text, isSnippet: true, at: date, clipboardProvider: { "" }) ?? text
    }
}
