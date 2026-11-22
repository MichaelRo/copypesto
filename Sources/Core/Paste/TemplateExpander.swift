// SPDX-License-Identifier: MIT
#if os(macOS)
import AppKit
#endif
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
///   {{selection}} — selected text in the active app at paste time (single-pass, never recursively expanded)
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

    /// iOS tells the person every time an app reads the clipboard, so there a caller that wants `{{clipboard}}` filled
    /// reads it after asking and passes its own provider.
    public static func liveClipboardText() -> String {
        #if os(macOS)
        AppPasteboard.reader.string(forType: .string) ?? ""
        #else
        ""
        #endif
    }

    /// Whether pasting `text` will read the live clipboard, so nothing reads it (and keeps it) for any other clip.
    public static func referencesClipboard(in text: String) -> Bool {
        text.contains("{{clipboard}}")
    }

    /// Whether pasting `text` will read the active selection from the target app.
    public static func referencesSelection(in text: String) -> Bool {
        text.contains("{{selection}}")
    }

    /// Whether `token` (the text between the braces) is something Pesto fills in by itself: a date, the clipboard, the
    /// selection, the app,
    /// a new ID or the caret.
    public static func isFill(_ token: String) -> Bool {
        [
            "date", "time", "datetime", "isodate", "weekday", "clipboard", "selection", "uuid", "cursor", "app"
        ].contains(token)
            || relativeDayOffset(from: token) != nil
    }

    public static func containsPlaceholders(_ text: String) -> Bool {
        text.contains("{{")
    }

    /// Whether every placeholder in `text` is one Pesto fills alone, without the person, the clipboard or the target
    /// app: a date, a time, a new ID or the caret. AutoFill inserts only such a snippet (ADR 0051).
    public static func fillsWithoutAsking(_ text: String) -> Bool {
        guard let regex = tokenRegex else { return false }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).allSatisfy { match in
            let token = ns.substring(with: match.range(at: 1))
            return isFill(token) && !["clipboard", "app", "selection"].contains(token)
        }
    }

    /// True when the template needs no pasteboard, frontmost-app or selection context (safe for AutoFill fill-in).
    public static func fillsWithoutSystemContext(_ text: String) -> Bool {
        guard let regex = tokenRegex else { return false }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).allSatisfy { match in
            let token = ns.substring(with: match.range(at: 1))
            return !["clipboard", "app", "selection"].contains(token)
        }
    }

    private static let optionalOpen: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\{\{optional:([^\n}]+)\}\}"#
    )

    private struct ExpansionOptions {
        let date: Date
        let fills: SnippetFills
        let targetApp: String
    }

    /// The text after expansion, or nil when nothing should change: only a snippet is expanded, so Helm, Jinja or
    /// Handlebars text that contains double braces pastes as it was copied.
    public static func expansion(
        of text: String,
        isSnippet: Bool,
        at date: Date = .now,
        fills: SnippetFills = SnippetFills(),
        targetApp: String = "",
        clipboardProvider: () -> String = liveClipboardText,
        selectionProvider: () -> String = { "" }
    )
        -> String?
    {
        guard isSnippet, containsPlaceholders(text) else { return nil }
        return expandSinglePass(
            text,
            options: ExpansionOptions(date: date, fills: fills, targetApp: targetApp),
            clipboardProvider: clipboardProvider,
            selectionProvider: selectionProvider
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
        clipboardProvider: () -> String = liveClipboardText,
        selectionProvider: () -> String = { "" }
    )
        -> (text: String, charactersAfterCursor: Int?)?
    {
        guard isSnippet, containsPlaceholders(text) else { return nil }
        let result = expandSinglePass(
            text,
            options: ExpansionOptions(date: date, fills: fills, targetApp: targetApp),
            clipboardProvider: clipboardProvider,
            selectionProvider: selectionProvider
        )
        return (result.text, result.charactersAfterCursor)
    }

    #if os(macOS)
    /// Expands tokens inside a rich-text payload, keeping proportional prose styling (bold, italic, links, colors) and
    /// dropping purely monospaced formatting so a template copied from a code editor never pastes as a code block.
    @MainActor
    public static func expandRichPayload(
        _ rich: RichTextPayload,
        at date: Date = .now,
        fills: SnippetFills = SnippetFills(),
        targetApp: String = "",
        clipboardProvider: () -> String = liveClipboardText,
        selectionProvider: () -> String = { "" }
    )
        -> RichTextPayload?
    {
        guard let regex = tokenRegex else { return nil }
        let attributed: NSAttributedString? = if let rtfd = rich.rtfd {
            NSAttributedString(rtfd: rtfd, documentAttributes: nil)
        } else if let rtf = rich.rtf {
            NSAttributedString(rtf: rtf, documentAttributes: nil)
        } else {
            nil
        }
        guard let attributed, attributed.length > 0, !isMonospacedOnly(attributed) else { return nil }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        resolveOptionalSections(in: mutable, included: fills.included)
        let nsText = mutable.string as NSString
        let matches = regex.matches(in: mutable.string, range: NSRange(location: 0, length: nsText.length))
        let options = ExpansionOptions(date: date, fills: fills, targetApp: targetApp)
        var cachedClipboard: String?
        var cachedSelection: String?
        for match in matches.reversed() {
            let token = (mutable.string as NSString).substring(with: match.range(at: 1))
            if token == "cursor" {
                mutable.deleteCharacters(in: match.range)
            } else if let replaced = replacement(
                for: token,
                options: options,
                clipboard: {
                    if let cachedClipboard { return cachedClipboard }
                    let value = clipboardProvider()
                    cachedClipboard = value
                    return value
                },
                selection: {
                    if let cachedSelection { return cachedSelection }
                    let value = selectionProvider()
                    cachedSelection = value
                    return value
                }
            ) {
                mutable.replaceCharacters(in: match.range, with: replaced)
            }
        }
        let fullRange = NSRange(location: 0, length: mutable.length)
        if rich.rtfd != nil, let rtfd = mutable.rtfd(from: fullRange, documentAttributes: [:]) {
            let rtf = rich.rtf != nil ? mutable.rtf(from: fullRange, documentAttributes: [:]) : nil
            return RichTextPayload(rtf: rtf, rtfd: rtfd, html: nil)
        }
        guard let rtf = mutable.rtf(from: fullRange, documentAttributes: [:]) else { return nil }
        return RichTextPayload(rtf: rtf, rtfd: nil, html: nil)
    }

    private static func isMonospacedOnly(_ attributed: NSAttributedString) -> Bool {
        var sawFont = false
        var hasProportionalFont = false
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.font, in: full) { value, _, stop in
            guard let font = value as? NSFont else { return }
            sawFont = true
            let name = font.fontName
            let family = font.familyName ?? ""
            let isMono = font.isFixedPitch
                || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
                || name.localizedCaseInsensitiveContains("mono")
                || name.localizedCaseInsensitiveContains("menlo")
                || name.localizedCaseInsensitiveContains("courier")
                || name.localizedCaseInsensitiveContains("consolas")
                || family.localizedCaseInsensitiveContains("mono")
            if !isMono {
                hasProportionalFont = true
                stop.pointee = true
            }
        }
        return sawFont && !hasProportionalFont
    }

    private static func resolveOptionalSections(in mutable: NSMutableAttributedString, included: Set<String>) {
        guard mutable.string.contains("{{optional:"), let opener = optionalOpen else { return }
        while true {
            let ns = mutable.string as NSString
            let closer = ns.range(of: "{{/optional}}")
            guard closer.location != NSNotFound else { return }
            let before = NSRange(location: 0, length: closer.location)
            guard let open = opener.matches(in: mutable.string, range: before).last else { return }
            let label = ns.substring(with: open.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if included.contains(label) {
                mutable.deleteCharacters(in: closer)
                mutable.deleteCharacters(in: open.range)
            } else {
                let whole = NSRange(location: open.range.location, length: closer.upperBound - open.range.location)
                mutable.deleteCharacters(in: whole)
            }
        }
    }
    #endif

    /// Returns `text` with all known `{{placeholder}}` tokens replaced.
    /// Unknown tokens (e.g. `{{name}}`) are left untouched.
    public static func expand(
        _ text: String,
        at date: Date = .now,
        clipboardProvider: () -> String = liveClipboardText,
        selectionProvider: () -> String = { "" }
    )
        -> String
    {
        guard containsPlaceholders(text) else { return text }
        return expandSinglePass(
            text,
            options: ExpansionOptions(date: date, fills: SnippetFills(), targetApp: ""),
            clipboardProvider: clipboardProvider,
            selectionProvider: selectionProvider
        )
        .text
    }

    private static func expandSinglePass(
        _ source: String,
        options: ExpansionOptions,
        clipboardProvider: () -> String,
        selectionProvider: () -> String
    )
        -> (text: String, charactersAfterCursor: Int?)
    {
        guard let regex = tokenRegex else { return (source, nil) }
        let text = resolvingOptionalSections(in: source, included: options.fills.included)
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return (text, nil) }

        var beforeCursor = ""
        var afterCursor = ""
        var sawCursor = false
        var cachedClipboard: String?
        var cachedSelection: String?
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
                options: options,
                clipboard: {
                    if let cachedClipboard { return cachedClipboard }
                    let value = clipboardProvider()
                    cachedClipboard = value
                    return value
                },
                selection: {
                    if let cachedSelection { return cachedSelection }
                    let value = selectionProvider()
                    cachedSelection = value
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
        options: ExpansionOptions,
        clipboard: () -> String,
        selection: () -> String
    )
        -> String?
    {
        if let field = FillInParser.field(fromToken: token), field.kind != .optional {
            return fillValue(for: field, in: options.fills)
        }
        switch token {
        case "app":
            return options.targetApp
        case "date":
            return dateString(from: options.date)
        case "time":
            return timeString(from: options.date)
        case "datetime":
            return dateTimeString(from: options.date)
        case "isodate":
            return isoDateString(from: options.date)
        case "weekday":
            return weekdayString(from: options.date)
        case "clipboard":
            return clipboard()
        case "selection":
            return selection()
        case "uuid":
            return UUID().uuidString.lowercased()
        default:
            if let offsetDays = relativeDayOffset(from: token),
               let shifted = Calendar.current.date(byAdding: .day, value: offsetDays, to: options.date)
            {
                return dateString(from: shifted)
            }
            return nil
        }
    }

    static func relativeDayOffset(from token: String) -> Int? {
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
