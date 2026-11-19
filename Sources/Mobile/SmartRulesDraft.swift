// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The rules of a smart collection while the editor is open: Core's `PredicateRuleSet`, edited through choices that
/// can only make a rule `PredicateValidator` accepts (the skill's constrained DSL, never a format string).
struct SmartRulesDraft: Equatable {
    /// Edit rules in place through `ruleSet`; add and remove them through the methods below, which keep the ids of
    /// the rows the editor draws in step. A row is found by its id, never by its position, so removing a rule while
    /// its field has the focus cannot hand the focus, or a later change, to its neighbour.
    var ruleSet: PredicateRuleSet
    private var identities: [GroupIdentity]

    private struct GroupIdentity {
        let id: UUID
        var rules: [UUID]
    }

    static func == (lhs: SmartRulesDraft, rhs: SmartRulesDraft) -> Bool {
        lhs.ruleSet == rhs.ruleSet
    }

    static var starter: SmartRulesDraft {
        SmartRulesDraft(ruleSet: PredicateRuleSet(
            combinator: .and, groups: [PredicateRuleSet.Group(combinator: .and, rules: [newRule()])]
        ))
    }

    static func newRule() -> PredicateRule {
        PredicateRule(field: .type, op: .equals, value: .string("text"))
    }

    /// Nil when the data is not a rule set this version can read and compile (a newer schema), so the editor leaves
    /// such a collection's rules alone.
    init?(data: Data?) {
        guard let data, let rules = try? SmartCollectionPredicate.decodeRuleSet(data),
              SmartCollectionPredicate.canCompileRuleSet(rules) else { return nil }
        ruleSet = rules
        identities = Self.identities(for: rules)
    }

    init(ruleSet: PredicateRuleSet) {
        self.ruleSet = ruleSet
        identities = Self.identities(for: ruleSet)
    }

    private static func identities(for ruleSet: PredicateRuleSet) -> [GroupIdentity] {
        ruleSet.groups.map { GroupIdentity(id: UUID(), rules: $0.rules.map { _ in UUID() }) }
    }

    var groupIDs: [UUID] {
        identities.map(\.id)
    }

    func ruleIDs(in group: UUID) -> [UUID] {
        identities.first { $0.id == group }?.rules ?? []
    }

    private func locate(rule id: UUID) -> (group: Int, rule: Int)? {
        for (group, identity) in identities.enumerated() {
            if let rule = identity.rules.firstIndex(of: id) { return (group, rule) }
        }
        return nil
    }

    func rule(_ id: UUID) -> PredicateRule? {
        locate(rule: id).map { ruleSet.groups[$0.group].rules[$0.rule] }
    }

    mutating func setRule(_ id: UUID, to rule: PredicateRule) {
        guard let place = locate(rule: id) else { return }
        ruleSet.groups[place.group].rules[place.rule] = rule
    }

    func combinator(of group: UUID) -> PredicateRuleSet.Combinator {
        groupIndex(group).map { ruleSet.groups[$0].combinator } ?? .and
    }

    mutating func setCombinator(of group: UUID, to combinator: PredicateRuleSet.Combinator) {
        guard let index = groupIndex(group) else { return }
        ruleSet.groups[index].combinator = combinator
    }

    private func groupIndex(_ id: UUID) -> Int? {
        identities.firstIndex { $0.id == id }
    }

    mutating func addRule(to group: UUID) {
        guard let index = groupIndex(group) else { return }
        ruleSet.groups[index].rules.append(Self.newRule())
        identities[index].rules.append(UUID())
    }

    /// A group keeps at least one rule.
    mutating func removeRule(_ id: UUID) {
        guard let place = locate(rule: id), ruleSet.groups[place.group].rules.count > 1 else { return }
        ruleSet.groups[place.group].rules.remove(at: place.rule)
        identities[place.group].rules.remove(at: place.rule)
    }

    mutating func addGroup() {
        ruleSet.groups.append(PredicateRuleSet.Group(combinator: .and, rules: [Self.newRule()]))
        identities.append(GroupIdentity(id: UUID(), rules: [UUID()]))
    }

    /// A collection keeps at least one group.
    mutating func removeGroup(_ id: UUID) {
        guard let index = groupIndex(id), ruleSet.groups.count > 1 else { return }
        ruleSet.groups.remove(at: index)
        identities.remove(at: index)
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
