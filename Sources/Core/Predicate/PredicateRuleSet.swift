// SPDX-License-Identifier: MIT
import Foundation

/// A versioned multi-group predicate. Groups are combined with `combinator` (AND/OR);
/// within each group, rules are combined with the group's own combinator.
///
/// v1 wire format (a bare `PredicateRule`) migrates on decode via `SmartCollectionPredicate`.
public struct PredicateRuleSet: Codable, Sendable, Equatable {
    public enum Combinator: String, Codable, Sendable { case and, or }

    public struct Group: Codable, Sendable, Equatable {
        public var combinator: Combinator
        public var rules: [PredicateRule]

        public init(combinator: Combinator, rules: [PredicateRule]) {
            self.combinator = combinator
            self.rules = rules
        }
    }

    public var schemaVersion: Int = 2
    public var combinator: Combinator
    public var groups: [Group]

    public init(combinator: Combinator, groups: [Group]) {
        self.combinator = combinator
        self.groups = groups
    }

    // MARK: - Evaluation

    public func matches<T: PredicateEvaluatable>(_ item: T) -> Bool {
        let groupResults = groups.map { group in
            let ruleResults = group.rules.map { rule in
                PredicateRuleSet.evaluateRule(rule, against: item)
            }
            return group.combinator == .and
                ? ruleResults.allSatisfy(\.self)
                : ruleResults.contains { $0 }
        }
        if groupResults.isEmpty { return true }
        return combinator == .and
            ? groupResults.allSatisfy(\.self)
            : groupResults.contains { $0 }
    }

    // MARK: - Rule evaluation

    private static func evaluateRule<T: PredicateEvaluatable>(_ rule: PredicateRule, against item: T) -> Bool {
        switch rule.field {
        case .type:
            return stringOp(rule.op, lhs: item.typeRaw, rhs: rule.value.stringValue ?? "")
        case .sourceBundleID:
            return stringOp(rule.op, lhs: item.sourceBundleID ?? "", rhs: rule.value.stringValue ?? "")
        case .sourceAppName:
            return stringOp(rule.op, lhs: item.sourceAppName ?? "", rhs: rule.value.stringValue ?? "")
        case .previewText:
            return stringOp(rule.op, lhs: item.displayPreviewText, rhs: rule.value.stringValue ?? "")
        case .detectedLanguage:
            return stringOp(rule.op, lhs: item.detectedLanguage ?? "", rhs: rule.value.stringValue ?? "")
        case .sensitivity:
            return stringOp(rule.op, lhs: item.sensitivityRaw ?? "", rhs: rule.value.stringValue ?? "")
        case .tags:
            let val = rule.value.stringValue ?? ""
            return item.tags.contains { stringOp(rule.op, lhs: $0, rhs: val) }
        case .isPinned:
            return rule.op == .isTrue ? item.isPinned : !item.isPinned
        case .isRemote:
            return rule.op == .isTrue ? item.isRemote : !item.isRemote
        case .timestamp:
            let secs = Double(rule.value.intValue ?? 0)
            let cutoff = Date.now.addingTimeInterval(-secs)
            return rule.op == .olderThanSeconds ? item.timestamp < cutoff : item.timestamp >= cutoff
        case .contentShape:
            return stringOp(rule.op, lhs: contentShape(of: item), rhs: rule.value.stringValue ?? "")
        }
    }

    /// Derives a content-shape token from the item without new stored columns.
    private static func contentShape<T: PredicateEvaluatable>(of item: T) -> String {
        switch item.typeRaw {
        case "url": return "link"
        case "color": return "color"
        case "file": return "file"
        case "image":
            let mime = item.mimeType ?? ""
            if mime == "com.compuserve.gif" || mime == "public.gif" { return "gif" }
            return "image"
        default:
            if let lang = item.detectedLanguage, !lang.isEmpty, lang != ClipboardType.markdownLanguage {
                if lang == "json" { return "json" }
                return "code"
            }
            let preview = item.displayPreviewText.lowercased()
            if preview.hasPrefix("curl ") { return "curl" }
            return "text"
        }
    }

    private static func stringOp(_ op: PredicateRule.Operator, lhs: String, rhs: String) -> Bool {
        switch op {
        case .equals: lhs.localizedCaseInsensitiveCompare(rhs) == .orderedSame
        case .notEquals: lhs.localizedCaseInsensitiveCompare(rhs) != .orderedSame
        case .contains: lhs.localizedCaseInsensitiveContains(rhs)
        case .beginsWith: lhs.lowercased().hasPrefix(rhs.lowercased())
        case .endsWith: lhs.lowercased().hasSuffix(rhs.lowercased())
        default: false
        }
    }
}
