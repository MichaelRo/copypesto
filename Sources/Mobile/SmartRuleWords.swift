// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// What the smart-collection editor calls fields, conditions and values. Core stores raw values and never renames one;
/// these are only the words on the screen.
enum SmartRuleWords {
    struct AgeChoice: Equatable {
        let seconds: Int
        let title: String
    }

    static var ageChoices: [AgeChoice] {
        [
            AgeChoice(seconds: 3600, title: String(localized: "An hour")),
            AgeChoice(seconds: 86_400, title: String(localized: "A day")),
            AgeChoice(seconds: 7 * 86_400, title: String(localized: "A week")),
            AgeChoice(seconds: 30 * 86_400, title: String(localized: "A month")),
            AgeChoice(seconds: 365 * 86_400, title: String(localized: "A year"))
        ]
    }

    static func ageTitle(seconds: Int) -> String {
        ageChoices.first { $0.seconds == seconds }?.title
            ?? Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .wide))
    }

    static func title(of field: PredicateRule.Field) -> String {
        switch field {
        case .type: String(localized: "Kind")
        case .sourceBundleID: String(localized: "App ID")
        case .sourceAppName: String(localized: "App")
        case .previewText: String(localized: "Text")
        case .timestamp: String(localized: "Copied")
        case .isPinned: String(localized: "Pinned")
        case .isRemote: String(localized: "Copied on")
        case .detectedLanguage: String(localized: "Language")
        case .sensitivity: String(localized: "Hidden Clip")
        case .tags: String(localized: "Tag")
        case .contentShape: String(localized: "Shape")
        }
    }

    static func title(of op: PredicateRule.Operator, field: PredicateRule.Field) -> String {
        switch op {
        case .equals: String(localized: "is")
        case .notEquals: String(localized: "is not")
        case .contains: String(localized: "contains")
        case .beginsWith: String(localized: "starts with")
        case .endsWith: String(localized: "ends with")
        case .olderThanSeconds: String(localized: "longer ago than")
        case .newerThanSeconds: String(localized: "more recently than")
        case .isTrue: remoteOrPinned(
                field,
                remote: String(localized: "another device"),
                pinned: String(localized: "is pinned")
            )
        case .isFalse:
            remoteOrPinned(
                field, remote: String(localized: "this device"),
                pinned: String(localized: "is not pinned")
            )
        }
    }

    private static func remoteOrPinned(_ field: PredicateRule.Field, remote: String, pinned: String) -> String {
        if field == .isRemote { remote } else { pinned }
    }

    /// The raw value a rule stores, and what to call it.
    static func choices(for field: PredicateRule.Field) -> [(value: String, title: String)]? {
        switch field {
        case .type:
            [
                ("text", String(localized: "Text")), ("url", String(localized: "Link")),
                ("image", String(localized: "Picture")), ("color", String(localized: "Color")),
                ("code", String(localized: "Code")), ("file", String(localized: "File"))
            ]
        case .contentShape:
            [
                ("text", String(localized: "Text")), ("link", String(localized: "Link")),
                ("code", String(localized: "Code")), ("json", "JSON"), ("curl", "cURL"),
                ("image", String(localized: "Picture")), ("gif", "GIF"), ("color", String(localized: "Color")),
                ("file", String(localized: "File"))
            ]
        case .sensitivity:
            SensitivityCategory.allCases.map { ($0.rawValue, $0.badgeLabel) }
        default:
            nil
        }
    }

    static func placeholder(for field: PredicateRule.Field) -> String {
        switch field {
        case .detectedLanguage: String(localized: "swift")
        case .tags: String(localized: "Tag name")
        case .sourceAppName: String(localized: "App name")
        case .sourceBundleID: String(localized: "com.example.app")
        default: String(localized: "Words")
        }
    }
}
