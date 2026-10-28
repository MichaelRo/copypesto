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
///   {{app}}       — name of the app being pasted into
///   {{input:…}}, {{choice:…}}, {{optional:…}}…{{/optional}} — values the person gives at paste time (`FillInParser`)
///
/// Expansion uses the user's current `Locale` and `TimeZone` so dates/times match the
/// system format the user expects. All replacements happen in a single pass.
public enum TemplateExpander {
    private static let tokenRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\{\{((?:(?!\}\}|\{\{)[^\n])+)\}\}"#
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

    private static let optionalOpen: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\{\{optional:([^\n}]+)\}\}"#
    )

    /// The text after expansion, or nil when nothing should change: only a snippet is expanded, so Helm, Jinja or
    /// Handlebars text that contains double braces pastes as it was copied.
    public static func expansion(
        of text: String,
        isSnippet: Bool,
        at date: Date = .now,
        fills: SnippetFills = SnippetFills(),
        targetApp: String = "",
        clipboardProvider: () -> String = liveClipboardText
    )
    -> String? {
        guard isSnippet, containsPlaceholders(text) else { return nil }
        return expandSinglePass(
            text, at: date, fills: fills, targetApp: targetApp, clipboardProvider: clipboardProvider
        ).text
    }

    /// The expansion with where `{{cursor}}` was: how many characters (as the caret moves over them, so a letter with
    /// its accents or an emoji counts once) follow the first cursor token. Nil when nothing should change.
    public static func expansionWithCaret(
        of text: String,
        isSnippet: Bool,
        at date: Date = .now,
        fills: SnippetFills = SnippetFills(),
        targetApp: String = "",
        clipboardProvider: () -> String = liveClipboardText
    )
    -> (text: String, charactersAfterCursor: Int?)? {
        guard isSnippet, containsPlaceholders(text) else { return nil }
        let result = expandSinglePass(
            text, at: date, fills: fills, targetApp: targetApp, clipboardProvider: clipboardProvider
        )
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
        return expandSinglePass(
            text,
            at: date,
            fills: SnippetFills(),
            targetApp: "",
            clipboardProvider: clipboardProvider
        )
        .text
    }

    private static func expandSinglePass(
        _ source: String,
        at date: Date,
        fills: SnippetFills,
        targetApp: String,
        clipboardProvider: () -> String
    )
    -> (text: String, charactersAfterCursor: Int?) {
        guard let regex = tokenRegex else { return (source, nil) }
        let text = resolvingOptionalSections(in: source, included: fills.included)
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
                fills: fills,
                targetApp: targetApp,
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

    /// Keeps the text of each optional section the person included and drops the rest, tags and fields with it. A
    /// section with no closing tag is left as typed. Runs on the template, never on what was typed into a field.
    private static func resolvingOptionalSections(in text: String, included: Set<String>) -> String {
        guard text.contains("{{optional:"), let opener = optionalOpen else { return text }
        var current = text
        while true {
            let ns = current as NSString
            let closer = ns.range(of: "{{/optional}}")
            guard closer.location != NSNotFound else { return current }
            let before = NSRange(location: 0, length: closer.location)
            guard let open = opener.matches(in: current, range: before).last else { return current }
            let label = ns.substring(with: open.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let inner = NSRange(location: open.range.upperBound, length: closer.location - open.range.upperBound)
            let kept = included.contains(label) ? ns.substring(with: inner) : ""
            let whole = NSRange(location: open.range.location, length: closer.upperBound - open.range.location)
            current = ns.replacingCharacters(in: whole, with: kept)
        }
    }

    private static func fillValue(for field: SnippetField, in fills: SnippetFills) -> String {
        if let value = fills.values[field.label] { return value }
        return field.defaultValue ?? ""
    }

    private static func replacement(
        for token: String,
        at date: Date,
        fills: SnippetFills,
        targetApp: String,
        clipboard: () -> String
    )
    -> String? {
        if let field = FillInParser.field(fromToken: token), field.kind != .optional {
            return fillValue(for: field, in: fills)
        }
        switch token {
        case "app":
            return targetApp
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
