// SPDX-License-Identifier: MIT
import Foundation

public struct CollectionSuggestion: Equatable, Sendable, Identifiable {
    public enum Group: Int, Sendable, CaseIterable {
        case fromYourClips
        case topics
        case starters
    }

    /// Stable across runs, so a suggestion keeps its place and a dismissed one can be remembered.
    public let id: String
    public let group: Group
    public let name: String
    public let symbol: String
    public let colorHex: String
    /// Clips in the history that the rule matches now; nil for a starter that matches nothing yet.
    public let matchCount: Int?
    /// One line in Pesto's voice for a starter; nil where the count says it all.
    public let blurb: String?
    public let ruleSet: PredicateRuleSet
}

/// What to offer in Settings → Collections: smart collections built from what the person actually copies, a few topics
/// found by clustering, and starters for a history too short to learn from. A suggestion is always a smart collection:
/// it fills itself, and creating one never moves a clip out of the collection it is in.
public enum CollectionSuggester {
    public static let thinHistory = 30
    private static let minimumForShape = 5
    private static let minimumForRareShape = 3
    private static let minimumForApp = 8
    private static let topicCoverage = 0.6
    private static let minimumForTopic = 3

    /// `topics` are the clusters `SmartCollectionSuggestions` found; a topic is offered only when a rule on its own
    /// key term still gathers most of it, because a collection that does not hold what was suggested is worse than
    /// none.
    public static func suggest<T: PredicateEvaluatable>(
        clips: [T],
        id: (T) -> UUID,
        existing: [PredicateRuleSet],
        topics: [SmartCollectionSuggestions.Suggestion] = [],
        dismissed: Set<String> = []
    )
    -> [CollectionSuggestion] {
        var candidates = fromClips(clips) + topicSuggestions(clips: clips, id: id, topics: topics)
        if clips.count < thinHistory {
            let taken = Set(candidates.map(\.id))
            candidates += starters().filter { !taken.contains($0.id) }
        }
        return candidates
            .filter { suggestion in
                !dismissed.contains(suggestion.id) && !existing.contains(suggestion.ruleSet)
            }
            .sorted {
                ($0.group.rawValue, -($0.matchCount ?? 0), $0.name) < (
                    $1.group.rawValue,
                    -($1.matchCount ?? 0),
                    $1.name
                )
            }
    }

    // MARK: - From the clips

    private static func fromClips(_ clips: [some PredicateEvaluatable]) -> [CollectionSuggestion] {
        var found: [CollectionSuggestion] = []
        for shape in Shape.allCases {
            let ruleSet = shape.ruleSet
            let count = clips.count(where: { ruleSet.matches($0) })
            guard count >= shape.minimum else { continue }
            found.append(shape.suggestion(group: .fromYourClips, count: count, blurb: nil))
        }

        let remote = clips.filter(\.isRemote).count
        if remote >= minimumForRareShape {
            found.append(CollectionSuggestion(
                id: "other-devices", group: .fromYourClips, name: "From other devices", symbol: "iphone.gen3",
                colorHex: "#5856D6", matchCount: remote, blurb: nil,
                ruleSet: single(.isRemote, .isTrue, .none)
            ))
        }

        let palette = ["#0A84FF", "#FF9F0A", "#BF5AF2"]
        let named = clips.compactMap { clip -> (bundle: String, name: String)? in
            guard let bundle = clip.sourceBundleID, !bundle.isEmpty, let name = clip.sourceAppName,
                  !name.isEmpty else { return nil }
            return (bundle, name)
        }
        let byApp = Dictionary(grouping: named, by: \.bundle)
        let share = max(minimumForApp, clips.count / 10)
        let top = byApp.filter { $0.value.count >= share }.sorted { $0.value.count > $1.value.count }.prefix(3)
        for (index, entry) in top.enumerated() {
            guard let name = entry.value.first?.name else { continue }
            found.append(CollectionSuggestion(
                id: "app-\(entry.key)", group: .fromYourClips, name: "From \(name)", symbol: "square.stack",
                colorHex: palette[index % palette.count], matchCount: entry.value.count, blurb: nil,
                ruleSet: single(.sourceBundleID, .equals, .string(entry.key))
            ))
        }
        return found
    }

    private static let multiTermCoverage = 0.5

    // MARK: - Topics

    private static func topicSuggestions<T: PredicateEvaluatable>(
        clips: [T], id: (T) -> UUID, topics: [SmartCollectionSuggestions.Suggestion]
    )
    -> [CollectionSuggestion] {
        let byID = Dictionary(clips.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return topics.compactMap { topic in
            guard !topic.name.isEmpty, topic.name != "Clipboard Group" else { return nil }
            let members = topic.itemIDs.compactMap { byID[$0] }
            guard !members.isEmpty else { return nil }
            for term in topic.keyTerms where !seen.contains(term) {
                let ruleSet = single(.previewText, .contains, .string(term))
                let covered = members.count(where: { ruleSet.matches($0) })
                let total = clips.count(where: { ruleSet.matches($0) })
                guard Double(covered) / Double(members.count) >= topicCoverage, total >= minimumForTopic else {
                    continue
                }
                seen.insert(term)
                return CollectionSuggestion(
                    id: "topic-\(term)", group: .topics, name: topic.name, symbol: "tag", colorHex: "#30B0C7",
                    matchCount: total, blurb: nil, ruleSet: ruleSet
                )
            }
            let freshTerms = Array(topic.keyTerms.filter { !seen.contains($0) }.prefix(3))
            guard freshTerms.count >= 2 else { return nil }
            let combinedRule = PredicateRuleSet(
                combinator: .and,
                groups: [PredicateRuleSet.Group(
                    combinator: .or,
                    rules: freshTerms.map { PredicateRule(field: .previewText, op: .contains, value: .string($0)) }
                )]
            )
            let covered = members.count(where: { combinedRule.matches($0) })
            let total = clips.count(where: { combinedRule.matches($0) })
            guard Double(covered) / Double(members.count) >= multiTermCoverage, total >= minimumForTopic else {
                return nil
            }
            freshTerms.forEach { seen.insert($0) }
            return CollectionSuggestion(
                id: "topic-\(freshTerms.joined(separator: "-"))",
                group: .topics,
                name: topic.name,
                symbol: "tag",
                colorHex: "#30B0C7",
                matchCount: total,
                blurb: nil,
                ruleSet: combinedRule
            )
        }
    }

    // MARK: - Starters

    public static func starters() -> [CollectionSuggestion] {
        let today = CollectionSuggestion(
            id: "today", group: .starters, name: "Today", symbol: "sun.max", colorHex: "#FF9F0A", matchCount: nil,
            blurb: "Whatever you copied in the last day, in one place.",
            ruleSet: single(.timestamp, .newerThanSeconds, .int(86_400))
        )
        let shapes = Shape.allCases.map { shape in
            shape.suggestion(group: .starters, count: nil, blurb: shape.starterBlurb)
        }
        return shapes + [today]
    }

    // MARK: - Shapes

    private enum Shape: CaseIterable {
        case links, code, pictures, colors, files

        var minimum: Int {
            switch self {
            case .links, .code, .pictures: CollectionSuggester.minimumForShape
            case .colors, .files: CollectionSuggester.minimumForRareShape
            }
        }

        var shapes: [String] {
            switch self {
            case .links: ["link"]
            case .code: ["code", "json", "curl"]
            case .pictures: ["image", "gif"]
            case .colors: ["color"]
            case .files: ["file"]
            }
        }

        var ruleSet: PredicateRuleSet {
            PredicateRuleSet(combinator: .and, groups: [PredicateRuleSet.Group(
                combinator: .or,
                rules: shapes.map { PredicateRule(field: .contentShape, op: .equals, value: .string($0)) }
            )])
        }

        var id: String {
            "shape-\(name.lowercased())"
        }

        var name: String {
            switch self {
            case .links: "Links"
            case .code: "Code"
            case .pictures: "Pictures"
            case .colors: "Colors"
            case .files: "Files"
            }
        }

        var symbol: String {
            switch self {
            case .links: "link"
            case .code: "chevron.left.forwardslash.chevron.right"
            case .pictures: "photo"
            case .colors: "paintpalette"
            case .files: "doc"
            }
        }

        var colorHex: String {
            switch self {
            case .links: "#0A84FF"
            case .code: "#30B0C7"
            case .pictures: "#FF375F"
            case .colors: "#BF5AF2"
            case .files: "#8E8E93"
            }
        }

        var starterBlurb: String {
            switch self {
            case .links: "Every link you copy, ready when you need it."
            case .code: "Snippets, commands and JSON, kept where you can find them."
            case .pictures: "Screenshots and pictures, side by side."
            case .colors: "Every swatch you have copied."
            case .files: "The files you copy, in one place."
            }
        }

        func suggestion(group: CollectionSuggestion.Group, count: Int?, blurb: String?) -> CollectionSuggestion {
            CollectionSuggestion(
                id: id, group: group, name: name, symbol: symbol, colorHex: colorHex, matchCount: count,
                blurb: blurb, ruleSet: ruleSet
            )
        }
    }

    private static func single(
        _ field: PredicateRule.Field, _ op: PredicateRule.Operator, _ value: PredicateRule.Value
    )
    -> PredicateRuleSet {
        PredicateRuleSet(combinator: .and, groups: [PredicateRuleSet.Group(
            combinator: .and, rules: [PredicateRule(field: field, op: op, value: value)]
        )])
    }
}
