// SPDX-License-Identifier: MIT
import AppKit
import Foundation

/// Expands `{{placeholder}}` tokens in a string at paste time.
///
/// Supported placeholders:
///   {{date}}      — current date, locale-aware short format (e.g. "5/15/2026")
///   {{time}}      — current time, locale-aware short format (e.g. "2:30 PM")
///   {{datetime}}  — date + time separated by a space
///   {{isodate}}   — ISO-8601 date ("yyyy-MM-dd")
///   {{weekday}}   — full weekday name ("EEEE")
///   {{date+Nd}} / {{date-Nd}} — date offset by N days in locale-aware short format
///   {{clipboard}} — live plain-text clipboard content (single-pass, never recursively expanded)
///   {{uuid}}      — fresh lowercase UUID
///   {{cursor}}    — removed; the caret is moved back to it after the paste (`expansionWithCaret`)
///
/// Expansion uses the user's current `Locale` and `TimeZone` so dates/times match the
/// system format the user expects. All replacements happen in a single pass.
public enum TemplateExpander {
    private static let tokenRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\{\{([a-zA-Z0-9+-]+)\}\}"#
    )

    public static func liveClipboardText() -> String {
        AppPasteboard.reader.string(forType: .string) ?? ""
    }

    /// Whether pasting `text` will read the live clipboard, so nothing reads it (and keeps it) for any other clip.
    public static func referencesClipboard(in text: String) -> Bool {
        text.contains("{{clipboard}}")
    }

    public static func containsPlaceholders(_ text: String) -> Bool {
        text.contains("{{")
    }

    /// The text after expansion, or nil when nothing should change: only a snippet is expanded, so Helm, Jinja or
    /// Handlebars text that contains double braces pastes as it was copied.
    public static func expansion(
        of text: String,
        isSnippet: Bool,
        at date: Date = .now,
        clipboardProvider: () -> String = liveClipboardText
    )
    -> String? {
        guard isSnippet, containsPlaceholders(text) else { return nil }
        return expand(text, at: date, clipboardProvider: clipboardProvider)
    }

    /// The expansion with where `{{cursor}}` was: how many characters (as the caret moves over them, so a letter with
    /// its accents or an emoji counts once) follow the first cursor token. Nil when nothing should change.
    public static func expansionWithCaret(
        of text: String,
        isSnippet: Bool,
        at date: Date = .now,
        clipboardProvider: () -> String = liveClipboardText
    )
    -> (text: String, charactersAfterCursor: Int?)? {
        guard isSnippet, containsPlaceholders(text) else { return nil }
        let result = expandSinglePass(text, at: date, clipboardProvider: clipboardProvider)
        return (result.text, result.charactersAfterCursor)
    }

    /// Returns `text` with all known `{{placeholder}}` tokens replaced.
    /// Unknown tokens (e.g. `{{name}}`) are left untouched.
    public static func expand(
        _ text: String,
        at date: Date = .now,
        clipboardProvider: () -> String = liveClipboardText
    )
    -> String {
        guard containsPlaceholders(text) else { return text }
        return expandSinglePass(text, at: date, clipboardProvider: clipboardProvider).text
    }

    private static func expandSinglePass(
        _ text: String,
        at date: Date,
        clipboardProvider: () -> String
    )
    -> (text: String, charactersAfterCursor: Int?) {
        guard let regex = tokenRegex else { return (text, nil) }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return (text, nil) }

        var beforeCursor = ""
        var afterCursor = ""
        var sawCursor = false
        var cachedClipboard: String?
        var cursorLocation = 0

        func appendChunk(_ chunk: String) {
            if sawCursor {
                afterCursor += chunk
            } else {
                beforeCursor += chunk
            }
        }

        for match in matches {
            let matchRange = match.range
            if matchRange.location > cursorLocation {
                let prefixRange = NSRange(location: cursorLocation, length: matchRange.location - cursorLocation)
                appendChunk(nsText.substring(with: prefixRange))
            }
            let token = nsText.substring(with: match.range(at: 1))
            if token == "cursor" {
                sawCursor = true
            } else if let replaced = replacement(
                for: token,
                at: date,
                clipboard: {
                    if let cachedClipboard { return cachedClipboard }
                    let value = clipboardProvider()
                    cachedClipboard = value
                    return value
                }
            ) {
                appendChunk(replaced)
            } else {
                appendChunk(nsText.substring(with: matchRange))
            }
            cursorLocation = matchRange.location + matchRange.length
        }

        if cursorLocation < nsText.length {
            let trailingRange = NSRange(location: cursorLocation, length: nsText.length - cursorLocation)
            appendChunk(nsText.substring(with: trailingRange))
        }

        return (beforeCursor + afterCursor, sawCursor ? afterCursor.count : nil)
    }

    private static func replacement(for token: String, at date: Date, clipboard: () -> String) -> String? {
        switch token {
        case "date":
            return dateString(from: date)
        case "time":
            return timeString(from: date)
        case "datetime":
            return dateTimeString(from: date)
        case "isodate":
            return isoDateString(from: date)
        case "weekday":
            return weekdayString(from: date)
        case "clipboard":
            return clipboard()
        case "uuid":
            return UUID().uuidString.lowercased()
        default:
            if let offsetDays = relativeDayOffset(from: token),
               let shifted = Calendar.current.date(byAdding: .day, value: offsetDays, to: date)
            {
                return dateString(from: shifted)
            }
            return nil
        }
    }

    private static func relativeDayOffset(from token: String) -> Int? {
        guard token.hasPrefix("date+") || token.hasPrefix("date-"), token.hasSuffix("d") else {
            return nil
        }
        return Int(token.dropFirst(4).dropLast(1))
    }

    // MARK: - Formatters (lazily initialized, locale/timezone-aware)

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static func dateTimeString(from date: Date) -> String {
        "\(dateString(from: date)) \(timeString(from: date))"
    }

    private static func isoDateString(from date: Date) -> String {
        isoDateFormatter.string(from: date)
    }

    private static func weekdayString(from date: Date) -> String {
        weekdayFormatter.string(from: date)
    }
}
