// SPDX-License-Identifier: MIT
import Foundation

/// Reads the fill-in tokens of a snippet (`docs/design/snippets-and-suggestions.md`, ADR 0017). A malformed token is
/// not a field and pastes as typed.
public enum FillInParser {
    static let maxLabelLength = 60

    private static let tokenRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\{\{((?:(?!\}\}|\{\{)[^\n])+)\}\}"#
    )
    private static let attributeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\w+)="((?:[^"\\]|\\.)*)"|(\w+)"#
    )
    private static let attributeStart: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\s+(?:default=|options=|multiline(?:\s|$))"#
    )

    /// The fields a snippet asks for, in order of first appearance, each label once.
    public static func fields(in text: String) -> [SnippetField] {
        guard text.contains("{{"), let regex = tokenRegex else { return [] }
        let ns = text as NSString
        var seen = Set<String>()
        var result: [SnippetField] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let field = field(fromToken: ns.substring(with: match.range(at: 1))) else { continue }
            if field.kind == .optional, !hasClosingTag(after: match.range, in: ns) { continue }
            if seen.insert(field.label).inserted { result.append(field) }
        }
        return result
    }

    static let fieldStart = "\u{E000}"
    static let fieldSeparator = "\u{E001}"
    static let fieldEnd = "\u{E002}"
    static let optionalOpen = "\u{E003}"
    static let optionalOpenEnd = "\u{E004}"
    static let optionalClose = "\u{E005}"

    /// The text with each fill-in and `{{app}}` swapped for a marker the preview can read back, so the rest of the
    /// template is expanded as usual and the fields stay visible. Markers use private-use characters.
    static func markingFields(in text: String) -> String {
        guard let regex = tokenRegex else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let body = ns.substring(with: match.range(at: 1))
            var marker: String?
            if body == "app" {
                marker = fieldStart + "context" + fieldSeparator + "app" + fieldSeparator + fieldEnd
            } else if body == "/optional" {
                marker = optionalClose
            } else if let field = field(fromToken: body) {
                switch field.kind {
                case .text:
                    marker = fieldStart + "input" + fieldSeparator + field.label + fieldSeparator
                        + (field.defaultValue ?? "") + fieldEnd
                case let .choice(options):
                    marker = fieldStart + "choice" + fieldSeparator + field.label + fieldSeparator
                        + options.joined(separator: " / ") + fieldEnd
                case .optional:
                    marker = optionalOpen + field.label + optionalOpenEnd
                }
            }
            guard let marker else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)) + marker
            cursor = match.range.upperBound
        }
        return result + ns.substring(from: cursor)
    }

    /// The fields of several snippets together, each label once, so a stack asks everything up front.
    public static func fields(inAll texts: [String]) -> [SnippetField] {
        var seen = Set<String>()
        return texts.flatMap { fields(in: $0) }.filter { seen.insert($0.label).inserted }
    }

    /// Whether pasting `text` has to ask the person anything: a `{{app}}` or a date fills itself in.
    public static func needsPrompt(_ text: String) -> Bool {
        !fields(in: text).isEmpty
    }

    static func field(fromToken body: String) -> SnippetField? {
        if body.hasPrefix("input:") { return inputField(String(body.dropFirst(6))) }
        if body.hasPrefix("choice:") { return choiceField(String(body.dropFirst(7))) }
        if body.hasPrefix("optional:") {
            let label = body.dropFirst(9).trimmingCharacters(in: .whitespaces)
            return validLabel(label) ? SnippetField(label: label, kind: .optional, defaultValue: nil) : nil
        }
        return nil
    }

    private static func inputField(_ rest: String) -> SnippetField? {
        let (label, attributes) = split(rest)
        guard validLabel(label) else { return nil }
        return SnippetField(
            label: label,
            kind: .text(multiline: attributes.flags.contains("multiline")),
            defaultValue: attributes.values["default"]
        )
    }

    private static func choiceField(_ rest: String) -> SnippetField? {
        let (label, attributes) = split(rest)
        guard validLabel(label), let raw = attributes.values["options"] else { return nil }
        let options = raw.split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = options.first else { return nil }
        let chosen = attributes.values["default"].flatMap { options.contains($0) ? $0 : nil } ?? first
        return SnippetField(label: label, kind: .choice(options), defaultValue: chosen)
    }

    private static func validLabel(_ label: String) -> Bool {
        !label.isEmpty && label.count <= maxLabelLength
    }

    private static func split(_ rest: String) -> (label: String, attributes: (
        values: [String: String],
        flags: Set<String>
    )) {
        let ns = rest as NSString
        let full = NSRange(location: 0, length: ns.length)
        let boundary = attributeStart?.firstMatch(in: rest, range: full)?.range.location ?? ns.length
        let label = ns.substring(to: boundary).trimmingCharacters(in: .whitespaces)
        let attributeText = ns.substring(from: boundary)
        var values: [String: String] = [:]
        var flags = Set<String>()
        let attributeNS = attributeText as NSString
        for match in attributeRegex?.matches(
            in: attributeText,
            range: NSRange(location: 0, length: attributeNS.length)
        ) ?? [] {
            if match.range(at: 1).location != NSNotFound {
                let value = attributeNS.substring(with: match.range(at: 2))
                values[attributeNS.substring(with: match.range(at: 1))] = unescaped(value)
            } else {
                flags.insert(attributeNS.substring(with: match.range(at: 3)))
            }
        }
        return (label, (values, flags))
    }

    private static func unescaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func hasClosingTag(after range: NSRange, in text: NSString) -> Bool {
        let tail = NSRange(location: range.upperBound, length: text.length - range.upperBound)
        return text.range(of: "{{/optional}}", range: tail).location != NSNotFound
    }
}
