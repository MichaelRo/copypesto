// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("PredicateRuleSet")
struct PredicateRuleSetTests {
    // MARK: - Round-trip

    @Test("v2 rule-set encodes and decodes unchanged")
    func whenV2RuleSet_thenRoundTrip() throws {
        let ruleSet = PredicateRuleSet(
            combinator: .and,
            groups: [
                PredicateRuleSet.Group(
                    combinator: .or,
                    rules: [
                        PredicateRule(field: .type, op: .equals, value: .string("url")),
                        PredicateRule(field: .type, op: .equals, value: .string("text"))
                    ]
                ),
                PredicateRuleSet.Group(
                    combinator: .and,
                    rules: [
                        PredicateRule(field: .isPinned, op: .isTrue, value: .none)
                    ]
                )
            ]
        )
        let data = try SmartCollectionPredicate.encodeRuleSet(ruleSet)
        let decoded = try SmartCollectionPredicate.decodeRuleSet(data)
        #expect(decoded == ruleSet)
    }

    // MARK: - v1 → v2 migration

    @Test("v1 single-rule JSON migrates to a single-group rule-set on decode")
    func whenV1JSON_thenMigratesAsOneGroupOneRule() throws {
        let v1Rule = PredicateRule(field: .sourceBundleID, op: .equals, value: .string("com.apple.Safari"))
        let v1Data = try SmartCollectionPredicate.encode(v1Rule)

        let ruleSet = try SmartCollectionPredicate.decodeRuleSet(v1Data)
        #expect(ruleSet.schemaVersion == 2)
        #expect(ruleSet.combinator == .and)
        #expect(ruleSet.groups.count == 1)
        #expect(ruleSet.groups[0].combinator == .and)
        #expect(ruleSet.groups[0].rules.count == 1)
        #expect(ruleSet.groups[0].rules[0] == v1Rule)
    }

    // MARK: - Evaluation: single group AND

    @Test("AND group matches only when all rules match")
    func whenAndGroup_thenAllRulesMustMatch() {
        let ruleSet = PredicateRuleSet(
            combinator: .and,
            groups: [
                PredicateRuleSet.Group(
                    combinator: .and,
                    rules: [
                        PredicateRule(field: .type, op: .equals, value: .string("text")),
                        PredicateRule(field: .isPinned, op: .isFalse, value: .none)
                    ]
                )
            ]
        )
        let textNotPinned = MockItem(typeRaw: "text", isPinned: false)
        let textPinned = MockItem(typeRaw: "text", isPinned: true)
        let urlNotPinned = MockItem(typeRaw: "url", isPinned: false)

        #expect(ruleSet.matches(textNotPinned))
        #expect(!ruleSet.matches(textPinned))
        #expect(!ruleSet.matches(urlNotPinned))
    }

    // MARK: - Evaluation: single group OR

    @Test("OR group matches when any rule matches")
    func whenOrGroup_thenAnyRuleMayMatch() {
        let ruleSet = PredicateRuleSet(
            combinator: .and,
            groups: [
                PredicateRuleSet.Group(
                    combinator: .or,
                    rules: [
                        PredicateRule(field: .type, op: .equals, value: .string("url")),
                        PredicateRule(field: .type, op: .equals, value: .string("text"))
                    ]
                )
            ]
        )
        #expect(ruleSet.matches(MockItem(typeRaw: "url")))
        #expect(ruleSet.matches(MockItem(typeRaw: "text")))
        #expect(!ruleSet.matches(MockItem(typeRaw: "image")))
    }

    // MARK: - Evaluation: multi-group AND between groups

    @Test("top-level AND requires all groups to match")
    func whenTopLevelAnd_thenAllGroupsMustMatch() {
        let ruleSet = PredicateRuleSet(
            combinator: .and,
            groups: [
                PredicateRuleSet.Group(
                    combinator: .or,
                    rules: [
                        PredicateRule(field: .type, op: .equals, value: .string("url")),
                        PredicateRule(field: .type, op: .equals, value: .string("text"))
                    ]
                ),
                PredicateRuleSet.Group(
                    combinator: .and,
                    rules: [
                        PredicateRule(field: .isPinned, op: .isTrue, value: .none)
                    ]
                )
            ]
        )
        // url + pinned → both groups pass
        #expect(ruleSet.matches(MockItem(typeRaw: "url", isPinned: true)))
        // url + not pinned → second group fails
        #expect(!ruleSet.matches(MockItem(typeRaw: "url", isPinned: false)))
        // image + pinned → first group fails
        #expect(!ruleSet.matches(MockItem(typeRaw: "image", isPinned: true)))
    }

    // MARK: - Evaluation: multi-group OR between groups

    @Test("top-level OR passes when any group matches")
    func whenTopLevelOr_thenAnyGroupSuffices() {
        let ruleSet = PredicateRuleSet(
            combinator: .or,
            groups: [
                PredicateRuleSet.Group(
                    combinator: .and,
                    rules: [PredicateRule(field: .type, op: .equals, value: .string("url"))]
                ),
                PredicateRuleSet.Group(
                    combinator: .and,
                    rules: [PredicateRule(field: .isPinned, op: .isTrue, value: .none)]
                )
            ]
        )
        // url item — first group passes
        #expect(ruleSet.matches(MockItem(typeRaw: "url", isPinned: false)))
        // pinned text — second group passes
        #expect(ruleSet.matches(MockItem(typeRaw: "text", isPinned: true)))
        // image not pinned — neither group passes
        #expect(!ruleSet.matches(MockItem(typeRaw: "image", isPinned: false)))
    }

    // MARK: - canCompileRuleSet

    @Test("canCompileRuleSet accepts schemaVersion 2")
    func whenSchemaVersion2_thenCompilable() {
        let ruleSet = PredicateRuleSet(combinator: .and, groups: [])
        #expect(SmartCollectionPredicate.canCompileRuleSet(ruleSet))
    }

    // MARK: - contentShape field

    @Test("contentShape gif matches GIF mime type")
    func whenContentShapeGif_thenMatchesGifMime() {
        let ruleSet = PredicateRuleSet(
            combinator: .and,
            groups: [
                PredicateRuleSet.Group(
                    combinator: .and,
                    rules: [PredicateRule(field: .contentShape, op: .equals, value: .string("gif"))]
                )
            ]
        )
        let gifItem = MockItem(typeRaw: "image", mimeType: "com.compuserve.gif")
        let pngItem = MockItem(typeRaw: "image", mimeType: "public.png")
        #expect(ruleSet.matches(gifItem))
        #expect(!ruleSet.matches(pngItem))
    }

    @Test("contentShape link matches url type")
    func whenContentShapeLink_thenMatchesUrlType() {
        let ruleSet = PredicateRuleSet(
            combinator: .and,
            groups: [
                PredicateRuleSet.Group(
                    combinator: .and,
                    rules: [PredicateRule(field: .contentShape, op: .equals, value: .string("link"))]
                )
            ]
        )
        #expect(ruleSet.matches(MockItem(typeRaw: "url")))
        #expect(!ruleSet.matches(MockItem(typeRaw: "text")))
    }

    @Test("contentShape code matches detected language")
    func whenContentShapeCode_thenMatchesNonNilLanguage() {
        let ruleSet = PredicateRuleSet(
            combinator: .and,
            groups: [
                PredicateRuleSet.Group(
                    combinator: .and,
                    rules: [PredicateRule(field: .contentShape, op: .equals, value: .string("code"))]
                )
            ]
        )
        #expect(ruleSet.matches(MockItem(typeRaw: "text", detectedLanguage: "swift")))
        #expect(!ruleSet.matches(MockItem(typeRaw: "text", detectedLanguage: nil)))
    }
}

@Suite("A smart collection can select clips from another device")
struct RemotePredicateTests {
    private func ruleSet(_ op: PredicateRule.Operator) -> PredicateRuleSet {
        PredicateRuleSet(
            combinator: .and,
            groups: [PredicateRuleSet.Group(
                combinator: .and, rules: [PredicateRule(field: .isRemote, op: op, value: .none)]
            )]
        )
    }

    @Test("isTrue matches only clips that arrived from another device, and isFalse the rest")
    func whenIsRemoteRule_thenMatchesByOrigin() {
        let fromPhone = MockItem(typeRaw: "text", isRemote: true)
        let local = MockItem(typeRaw: "text")

        #expect(ruleSet(.isTrue).matches(fromPhone))
        #expect(!ruleSet(.isTrue).matches(local))
        #expect(ruleSet(.isFalse).matches(local))
        #expect(!ruleSet(.isFalse).matches(fromPhone))
    }

    @Test("a rule saved with the field survives encoding")
    func whenEncoded_thenRoundTrips() throws {
        let rule = PredicateRule(field: .isRemote, op: .isTrue, value: .none)

        let decoded = try JSONDecoder().decode(PredicateRule.self, from: JSONEncoder().encode(rule))

        #expect(decoded == rule)
    }
}

// MARK: - Test helper

struct MockItem: PredicateEvaluatable {
    var typeRaw: String = "text"
    var isPinned: Bool = false
    var isRemote: Bool = false
    var sourceBundleID: String?
    var sourceAppName: String?
    var previewText: String = ""
    var detectedLanguage: String?
    var sensitivityRaw: String?
    var tags: [String] = []
    var timestamp: Date = .now
    var mimeType: String?
}
