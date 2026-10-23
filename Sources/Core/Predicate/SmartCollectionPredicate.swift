// SPDX-License-Identifier: MIT
import Foundation

/// Serializes `PredicateRuleSet` (v2) and `PredicateRule` (v1) into `Data` stored on
/// `Pinboard.smartPredicateData`, and parses them back.
///
/// Decode always returns a `PredicateRuleSet`: v1 wire blobs (bare `PredicateRule` JSON)
/// are migrated to a single-group, AND/AND rule-set transparently.
public enum SmartCollectionPredicate {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder = JSONDecoder()

    // MARK: - v1 API (kept for backwards compat; still writes v1 wire format)

    public static func encode(_ rule: PredicateRule) throws -> Data {
        try PredicateValidator.validate(rule)
        return try encoder.encode(rule)
    }

    public static func decode(_ data: Data) throws -> PredicateRule {
        let rule = try decoder.decode(PredicateRule.self, from: data)
        try PredicateValidator.validate(rule)
        return rule
    }

    public static let supportedRuleVersions: ClosedRange<Int> = 1...1

    public static func canCompile(_ rule: PredicateRule) -> Bool {
        supportedRuleVersions.contains(rule.version)
    }

    // MARK: - v2 API

    public static func encodeRuleSet(_ ruleSet: PredicateRuleSet) throws -> Data {
        // The v1 encoder validates its rule; a rule set holds many, and an invalid one would otherwise be saved and
        // then
        // quietly match nothing.
        for rule in ruleSet.groups.flatMap(\.rules) {
            try PredicateValidator.validate(rule)
        }
        return try encoder.encode(ruleSet)
    }

    /// Decodes either a v2 `PredicateRuleSet` or a v1 `PredicateRule`, migrating v1 → v2.
    public static func decodeRuleSet(_ data: Data) throws -> PredicateRuleSet {
        // Try v2 first.
        let v2Failure: (any Error)?
        do {
            let ruleSet = try decoder.decode(PredicateRuleSet.self, from: data)
            if ruleSet.schemaVersion == 2 { return ruleSet }
            v2Failure = nil
        } catch {
            v2Failure = error
        }
        // Fall back to v1 — wrap the single rule into a single-group AND rule-set. A blob that has groups was meant to
        // be v2, so its own error is the one worth reporting, not the v1 decoder's complaint about missing fields.
        let looksLikeV2 = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["groups"] != nil
        if looksLikeV2, let v2Failure { throw v2Failure }
        let v1Rule = try decoder.decode(PredicateRule.self, from: data)
        return PredicateRuleSet(
            combinator: .and,
            groups: [PredicateRuleSet.Group(combinator: .and, rules: [v1Rule])]
        )
    }

    public static let supportedRuleSetVersions: ClosedRange<Int> = 1...2

    public static func canCompileRuleSet(_ ruleSet: PredicateRuleSet) -> Bool {
        supportedRuleSetVersions.contains(ruleSet.schemaVersion)
    }
}
