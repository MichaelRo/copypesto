// SPDX-License-Identifier: MIT
import Foundation

/// A value a snippet asks for when it is pasted: `{{input:Label}}`, `{{choice:Label options="a|b"}}` or an optional
/// section `{{optional:Label}}…{{/optional}}`.
public struct SnippetField: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case text(multiline: Bool)
        case choice([String])
        case optional
    }

    public let label: String
    public let kind: Kind
    public let defaultValue: String?

    public var id: String {
        label
    }

    public init(label: String, kind: Kind, defaultValue: String?) {
        self.label = label
        self.kind = kind
        self.defaultValue = defaultValue
    }

    /// The token that asks for this field, as the Add Snippet sheet writes it. An optional section is only the opening
    /// tag: the text it wraps and the closing tag are the person's.
    public var token: String {
        switch kind {
        case let .text(multiline):
            var parts = ["input:\(label)"]
            if let defaultValue { parts.append(#"default="\#(Self.escaped(defaultValue))""#) }
            if multiline { parts.append("multiline") }
            return "{{\(parts.joined(separator: " "))}}"
        case let .choice(options):
            var parts = ["choice:\(label)", #"options="\#(Self.escaped(options.joined(separator: "|")))""#]
            if let defaultValue, defaultValue != options.first {
                parts.append(#"default="\#(Self.escaped(defaultValue))""#)
            }
            return "{{\(parts.joined(separator: " "))}}"
        case .optional:
            return "{{optional:\(label)}}"
        }
    }

    /// What the Add Snippet sheet inserts: the token, and for an optional section its closing tag as well.
    public var insertion: String {
        kind == .optional ? token + "{{/optional}}" : token
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// What the person gave the prompt: a value per label, and which optional sections to keep.
public struct SnippetFills: Equatable, Sendable {
    public var values: [String: String]
    public var included: Set<String>

    public init(values: [String: String] = [:], included: Set<String> = []) {
        self.values = values
        self.included = included
    }
}

public extension SnippetFills {
    /// What the prompt starts with: a remembered value if there is one, else the field's default, the first choice, and
    /// every optional section off. A remembered choice that is no longer an option is ignored.
    static func initial(for fields: [SnippetField], remembered: [String: String] = [:]) -> SnippetFills {
        var fills = SnippetFills()
        for field in fields {
            switch field.kind {
            case .text:
                fills.values[field.label] = remembered[field.label] ?? field.defaultValue ?? ""
            case let .choice(options):
                let kept = remembered[field.label].flatMap { options.contains($0) ? $0 : nil }
                fills.values[field.label] = kept ?? field.defaultValue ?? options.first ?? ""
            case .optional:
                if remembered[field.label] == "1" { fills.included.insert(field.label) }
            }
        }
        return fills
    }
}
