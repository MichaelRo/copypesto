// SPDX-License-Identifier: MIT
import Foundation

/// Turns the fill-ins of other snippet tools into Pesto's: Raycast's `{argument}` and TextExpander's `%filltext`,
/// `%fillarea`, `%fillpopup` and `%fillpart` (ADR 0017).
enum FillInImport {
    private static let raycast: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<!\{)\{argument((?:\s+[^{}]*)?)\}(?!\})"#
    )
    private static let expanderField: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"%(filltext|fillarea|fillpopup|fillpart)((?::[^%\n]*)?)%"#
    )
    private static let attribute: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\w+)="([^"]*)""#
    )

    static func convert(_ text: String) -> String {
        guard text.contains("{argument") || text.contains("%fill") else { return text }
        return convertingExpander(convertingRaycast(text))
    }

    private static func convertingRaycast(_ text: String) -> String {
        replacing(raycast, in: text) { ns, match in
            let attributes = ns.substring(with: match.range(at: 1))
            var values: [String: String] = [:]
            let attributeNS = attributes as NSString
            for found in attribute?
                .matches(in: attributes, range: NSRange(location: 0, length: attributeNS.length)) ?? []
            {
                values[attributeNS.substring(with: found.range(at: 1))] = attributeNS
                    .substring(with: found.range(at: 2))
            }
            let label = clean(values["name"]) ?? "Argument"
            let options = (values["options"] ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let field = options.isEmpty
                ? SnippetField(label: label, kind: .text(multiline: false), defaultValue: clean(values["default"]))
                : SnippetField(label: label, kind: .choice(options), defaultValue: clean(values["default"]))
            return field.token
        }
    }

    private static func convertingExpander(_ text: String) -> String {
        let converted = replacing(expanderField, in: text) { ns, match in
            let kind = ns.substring(with: match.range(at: 1))
            let parts = ns.substring(with: match.range(at: 2)).split(separator: ":").map(String.init)
            var name: String?
            var defaultValue: String?
            var values: [String] = []
            for part in parts {
                if part.hasPrefix("name=") {
                    name = clean(String(part.dropFirst(5)))
                } else if part.hasPrefix("default=") {
                    defaultValue = clean(String(part.dropFirst(8)))
                } else {
                    values.append(part)
                }
            }
            let label = name ?? "Field"
            switch kind {
            case "fillpart":
                return SnippetField(label: label, kind: .optional, defaultValue: nil).token
            case "fillpopup":
                var options = values
                if let defaultValue, !options.contains(defaultValue) { options.insert(defaultValue, at: 0) }
                guard !options.isEmpty else { return ns.substring(with: match.range) }
                return SnippetField(label: label, kind: .choice(options), defaultValue: defaultValue).token
            default:
                return SnippetField(
                    label: label, kind: .text(multiline: kind == "fillarea"), defaultValue: defaultValue
                ).token
            }
        }
        return converted.replacingOccurrences(of: "%fillpartend%", with: "{{/optional}}")
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func replacing(
        _ regex: NSRegularExpression?,
        in text: String,
        with make: (NSString, NSTextCheckingResult) -> String
    )
    -> String {
        guard let regex else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += make(ns, match)
            cursor = match.range.upperBound
        }
        return result + ns.substring(from: cursor)
    }
}
