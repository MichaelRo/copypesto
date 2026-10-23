// SPDX-License-Identifier: MIT
import Foundation

/// Constrained DSL for smart pinboards. No raw NSPredicate format strings (injection risk).
/// User-built rules serialize to `Data` via Codable; the storage layer compiles them
/// into a `Predicate<ClipboardItem>` at query time.
public struct PredicateRule: Codable, Sendable, Equatable {
    /// Schema version of the rule, for forward-compat when pinboards sync in v2.
    public var version: Int = 1

    public var field: Field
    public var op: Operator
    public var value: Value

    public init(field: Field, op: Operator, value: Value) {
        self.field = field
        self.op = op
        self.value = value
    }
}

public extension PredicateRule {
    enum Field: String, Codable, Sendable, CaseIterable {
        case type // ClipboardItem.typeRaw
        case sourceBundleID
        case sourceAppName
        case previewText
        case timestamp
        case isPinned
        /// Copied on another device (iPhone, iPad or another Mac) and received through Universal Clipboard.
        case isRemote
        case detectedLanguage
        case sensitivity
        case tags
        /// Derived content shape: gif | image | link | code | json | curl | text | color | file.
        /// Computed at filter time — no new stored column.
        case contentShape
    }

    enum Operator: String, Codable, Sendable, CaseIterable {
        case equals
        case notEquals
        case contains
        case beginsWith
        case endsWith
        case olderThanSeconds
        case newerThanSeconds
        case isTrue
        case isFalse
    }

    enum Value: Codable, Sendable, Equatable {
        case string(String)
        case int(Int)
        case bool(Bool)
        case none

        public var stringValue: String? {
            if case let .string(s) = self { return s }
            return nil
        }

        public var intValue: Int? {
            if case let .int(i) = self { return i }
            return nil
        }

        public var boolValue: Bool? {
            if case let .bool(b) = self { return b }
            return nil
        }
    }
}

/// Constraint check: which (field, operator, valueKind) combos are accepted.
public enum PredicateValidator {
    public enum ValidationError: Swift.Error, Equatable, Sendable {
        case operatorNotAllowedForField(PredicateRule.Field, PredicateRule.Operator)
        case valueKindMismatch(expected: String, got: String)
    }

    public static func validate(_ rule: PredicateRule) throws {
        let allowed = allowedOperators(for: rule.field)
        guard allowed.contains(rule.op) else {
            throw ValidationError.operatorNotAllowedForField(rule.field, rule.op)
        }
        let expected = expectedValueKind(for: rule.op)
        let actual = valueKind(of: rule.value)
        if actual != expected, expected != "any" {
            throw ValidationError.valueKindMismatch(expected: expected, got: actual)
        }
    }

    public static func allowedOperators(for field: PredicateRule.Field) -> Set<PredicateRule.Operator> {
        switch field {
        case .type, .sourceBundleID, .sensitivity, .detectedLanguage, .contentShape:
            [.equals, .notEquals]
        case .sourceAppName, .previewText:
            [.equals, .notEquals, .contains, .beginsWith, .endsWith]
        case .tags:
            [.contains, .equals, .notEquals]
        case .timestamp:
            [.olderThanSeconds, .newerThanSeconds]
        case .isPinned, .isRemote:
            [.isTrue, .isFalse]
        }
    }

    public static func expectedValueKind(for op: PredicateRule.Operator) -> String {
        switch op {
        case .equals, .notEquals, .contains, .beginsWith, .endsWith: "string"
        case .olderThanSeconds, .newerThanSeconds: "int"
        case .isTrue, .isFalse: "none"
        }
    }

    public static func valueKind(of value: PredicateRule.Value) -> String {
        switch value {
        case .string: "string"
        case .int: "int"
        case .bool: "bool"
        case .none: "none"
        }
    }
}
