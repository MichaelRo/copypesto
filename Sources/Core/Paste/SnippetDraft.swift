// SPDX-License-Identifier: MIT
import Foundation

public struct SnippetPlaceholder: Equatable, Sendable {
    public let token: String
    public let meaning: String
}

/// What the Add Snippet sheet can say about the text so far. A snippet is a pinned clip that holds a `{{placeholder}}`
/// (`docs/design/snippets-and-suggestions.md`), so text without one would be saved but never listed: the sheet asks for
/// one instead.
public enum SnippetDraft: Equatable, Sendable {
    case empty
    case needsPlaceholder
    case ready

    public static let placeholders = [
        SnippetPlaceholder(token: "{{date}}", meaning: "today's date"),
        SnippetPlaceholder(token: "{{time}}", meaning: "the current time"),
        SnippetPlaceholder(token: "{{datetime}}", meaning: "the date and time"),
        SnippetPlaceholder(token: "{{isodate}}", meaning: "ISO date (2026-05-15)"),
        SnippetPlaceholder(token: "{{weekday}}", meaning: "the day of the week"),
        SnippetPlaceholder(token: "{{date+1d}}", meaning: "tomorrow's date"),
        SnippetPlaceholder(token: "{{clipboard}}", meaning: "current clipboard text"),
        SnippetPlaceholder(token: "{{uuid}}", meaning: "a new unique ID"),
        SnippetPlaceholder(token: "{{cursor}}", meaning: "removed when you paste")
    ]

    public static func evaluate(_ text: String) -> SnippetDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        return TemplateExpander.containsPlaceholders(trimmed) ? .ready : .needsPlaceholder
    }

    public struct InsertionStep: Equatable, Sendable {
        public let text: String
        public let cursorLocation: Int
        public let clampedRange: NSRange
    }

    /// Inserts `token` into `text` at the given UTF-16 `range` (clamped to `text`'s bounds) and returns the updated
    /// string along with the UTF-16 cursor location immediately after the inserted token.
    public static func inserting(_ token: String, into text: String, at range: NSRange) -> InsertionStep {
        let nsText = text as NSString
        let safeLocation = min(max(0, range.location), nsText.length)
        let safeLength = min(max(0, range.length), nsText.length - safeLocation)
        let clamped = NSRange(location: safeLocation, length: safeLength)
        let updated = nsText.replacingCharacters(in: clamped, with: token)
        let newCursor = safeLocation + (token as NSString).length
        return InsertionStep(text: updated, cursorLocation: newCursor, clampedRange: clamped)
    }
}
