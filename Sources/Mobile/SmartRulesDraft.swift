// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The rules of a smart collection while the editor is open: Core's `PredicateRuleSet`, edited through choices that
/// can only make a rule `PredicateValidator` accepts (the skill's constrained DSL, never a format string).
struct SmartRulesDraft: Equatable {
    var ruleSet: PredicateRuleSet

    static let starter = SmartRulesDraft(ruleSet: PredicateRuleSet(
        combinator: .and, groups: [PredicateRuleSet.Group(combinator: .and, rules: [newRule()])]
    ))

    static func newRule() -> PredicateRule {
        PredicateRule(field: .type, op: .equals, value: .string("text"))
    }

    /// Nil when the data is not a rule set this version can read and compile (a newer schema), so the editor leaves
    /// such a collection's rules alone.
    init?(data: Data?) {
        guard let data, let rules = try? SmartCollectionPredicate.decodeRuleSet(data),
              SmartCollectionPredicate.canCompileRuleSet(rules), !rules.groups.isEmpty else { return nil }
        ruleSet = rules
    }

    init(ruleSet: PredicateRuleSet) {
        self.ruleSet = ruleSet
    }

    /// What a person can choose to match on. An app's bundle id means nothing to someone on a phone, so it is offered
    /// only while a rule already uses it (a collection made on a Mac).
    var fields: [PredicateRule.Field] {
        let used = Set(ruleSet.groups.flatMap(\.rules).map(\.field))
        return PredicateRule.Field.allCases.filter { $0 != .sourceBundleID || used.contains(.sourceBundleID) }
    }

    private static let operatorOrder: [PredicateRule.Operator] = [
        .equals, .notEquals, .contains, .beginsWith, .endsWith, .newerThanSeconds, .olderThanSeconds, .isTrue,
        .isFalse
    ]

    static func operators(for field: PredicateRule.Field) -> [PredicateRule.Operator] {
        let allowed = PredicateValidator.allowedOperators(for: field)
        return operatorOrder.filter(allowed.contains)
    }

    /// A rule for `field` that is valid as it stands: its first operator and a value that suits it.
    static func rule(for field: PredicateRule.Field) -> PredicateRule {
        let op = operators(for: field).first ?? .equals
        let value: PredicateRule.Value = switch field {
        case .type: .string("text")
        case .contentShape: .string("text")
        case .sensitivity: .string(SensitivityCategory.allCases.first?.rawValue ?? "")
        case .timestamp: .int(SmartRuleWords.ageChoices[1].seconds)
        case .isPinned, .isRemote: PredicateRule.Value.none
        case .sourceBundleID, .sourceAppName, .previewText, .detectedLanguage, .tags: .string("")
        }
        return PredicateRule(field: field, op: op, value: value)
    }

    /// Each rule is valid and every text it asks for is filled in.
    var isComplete: Bool {
        ruleSet.groups.allSatisfy { group in
            !group.rules.isEmpty && group.rules.allSatisfy(Self.isComplete)
        }
    }

    static func isComplete(_ rule: PredicateRule) -> Bool {
        guard (try? PredicateValidator.validate(rule)) != nil else { return false }
        if let text = rule.value.stringValue {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    func encoded() throws -> Data {
        try SmartCollectionPredicate.encodeRuleSet(ruleSet)
    }
}
