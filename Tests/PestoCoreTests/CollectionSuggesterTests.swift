// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

private struct Clip: PredicateEvaluatable, Identifiable {
    let id = UUID()
    var typeRaw = "text"
    var isPinned = false
    var isRemote = false
    var sourceBundleID: String?
    var sourceAppName: String?
    var previewText = ""
    var detectedLanguage: String?
    var sensitivityRaw: String?
    var tags: [String] = []
    var timestamp = Date.now
    var mimeType: String?
}

private func clips(_ count: Int, _ make: (Int) -> Clip) -> [Clip] {
    (0..<count).map(make)
}

@Suite("Collection suggestions")
struct CollectionSuggesterTests {
    @Test("a kind of clip is offered once there are enough of it, with how many match")
    func whenEnoughLinks_thenLinksIsOfferedWithItsCount() throws {
        var history = clips(40) { Clip(previewText: "note \($0)") }
        history += clips(6) { Clip(typeRaw: "url", previewText: "https://example.com/\($0)") }

        let suggestions = CollectionSuggester.suggest(clips: history, id: \.id, existing: [])

        let links = try #require(suggestions.first { $0.id == "shape-links" })
        #expect(links.matchCount == 6)
        #expect(links.group == .fromYourClips)
        #expect(links.name == "Links")
    }

    @Test("a kind with too few clips is not offered while there is plenty of history")
    func whenTooFewLinks_thenNotOffered() {
        var history = clips(60) { Clip(previewText: "note \($0)") }
        history += clips(2) { _ in Clip(typeRaw: "url") }

        let suggestions = CollectionSuggester.suggest(clips: history, id: \.id, existing: [])

        #expect(!suggestions.contains { $0.id == "shape-links" })
    }

    @Test("the apps most clips come from are offered, most first, at most three")
    func whenManyClipsShareAnApp_thenTheAppIsOffered() {
        var history = clips(30) { Clip(
            sourceBundleID: "com.apple.Safari",
            sourceAppName: "Safari",
            previewText: "s\($0)"
        ) }
        history += clips(12) { Clip(sourceBundleID: "com.apple.Notes", sourceAppName: "Notes", previewText: "n\($0)") }
        history += clips(10) { Clip(
            sourceBundleID: "com.tinyspeck.slackmacgap",
            sourceAppName: "Slack",
            previewText: "k\($0)"
        ) }
        history += clips(9) { Clip(sourceBundleID: "com.apple.mail", sourceAppName: "Mail", previewText: "m\($0)") }
        history +=
            clips(9) { Clip(sourceBundleID: "com.apple.dt.Xcode", sourceAppName: "Xcode", previewText: "x\($0)") }

        let apps = CollectionSuggester.suggest(clips: history, id: \.id, existing: [])
            .filter { $0.id.hasPrefix("app-") }

        #expect(apps.map(\.name) == ["From Safari", "From Notes", "From Slack"])
        #expect(apps.first?.matchCount == 30)
    }

    @Test("copies from other devices are offered when there are a few")
    func whenSomeCopiesAreRemote_thenOtherDevicesIsOffered() {
        let history = clips(40) { Clip(isRemote: $0 < 4, previewText: "c\($0)") }

        let suggestions = CollectionSuggester.suggest(clips: history, id: \.id, existing: [])

        #expect(suggestions.first { $0.id == "other-devices" }?.matchCount == 4)
    }

    @Test("a collection the person already has is not offered again")
    func whenTheRuleExists_thenItIsLeftOut() throws {
        let history = clips(40) { Clip(typeRaw: $0 < 8 ? "url" : "text", previewText: "c\($0)") }
        let first = CollectionSuggester.suggest(clips: history, id: \.id, existing: [])
        let links = try #require(first.first { $0.id == "shape-links" })

        let again = CollectionSuggester.suggest(clips: history, id: \.id, existing: [links.ruleSet])

        #expect(!again.contains { $0.id == "shape-links" })
    }

    @Test("a dismissed suggestion stays away")
    func whenDismissed_thenItIsLeftOut() {
        let history = clips(40) { Clip(typeRaw: $0 < 8 ? "url" : "text", previewText: "c\($0)") }

        let suggestions = CollectionSuggester.suggest(
            clips: history,
            id: \.id,
            existing: [],
            dismissed: ["shape-links"]
        )

        #expect(!suggestions.contains { $0.id == "shape-links" })
    }

    @Test("a short history gets starters, in Pesto's voice, and a long one does not")
    func whenHistoryIsThin_thenStartersAreOffered() {
        let thin = CollectionSuggester.suggest(clips: clips(4) { Clip(previewText: "c\($0)") }, id: \.id, existing: [])
        let long = CollectionSuggester.suggest(clips: clips(80) { Clip(previewText: "c\($0)") }, id: \.id, existing: [])

        let starters = thin.filter { $0.group == .starters }
        #expect(starters.map(\.name).sorted() == ["Code", "Colors", "Files", "Links", "Pictures", "Today"])
        #expect(starters.allSatisfy { ($0.blurb ?? "").hasSuffix(".") && $0.matchCount == nil })
        #expect(!long.contains { $0.group == .starters })
    }

    @Test("a starter gives way to the same suggestion built from real clips")
    func whenLinksHaveEnoughClips_thenOnlyTheCountedOneIsOffered() {
        let history = clips(12) { Clip(typeRaw: $0 < 6 ? "url" : "text", previewText: "c\($0)") }

        let links = CollectionSuggester.suggest(clips: history, id: \.id, existing: [])
            .filter { $0.id == "shape-links" }

        #expect(links.count == 1)
        #expect(links.first?.group == .fromYourClips)
    }

    @Test("every suggestion is a smart collection with a rule that is accepted")
    func whenSuggested_thenRulesAreValidAndEncode() throws {
        let history = clips(6) { Clip(typeRaw: "url", previewText: "c\($0)") }

        for suggestion in CollectionSuggester.suggest(clips: history, id: \.id, existing: []) {
            _ = try SmartCollectionPredicate.encodeRuleSet(suggestion.ruleSet)
            #expect(!suggestion.name.isEmpty && !suggestion.symbol.isEmpty)
        }
    }

    @Test("ids are unique, so a list keyed by them never collides")
    func whenSuggested_thenIDsAreUnique() {
        var history = clips(10) { _ in
            Clip(typeRaw: "url", sourceBundleID: "com.apple.Safari", sourceAppName: "Safari")
        }
        history += clips(10) { Clip(typeRaw: "color", previewText: "#00\($0)") }

        let ids = CollectionSuggester.suggest(clips: history, id: \.id, existing: []).map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test("a topic is offered only when a rule on its key term gathers most of it, and never as a generic group")
    func whenTopicsAreChecked_thenOnlyCoveredOnesSurvive() {
        let trip = clips(5) { Clip(previewText: "flight to Lisbon \($0)") }
        let mixed = clips(5) { Clip(previewText: $0 < 2 ? "invoice \($0)" : "something else \($0)") }
        let history = trip + mixed + clips(30) { Clip(previewText: "filler \($0)") }
        let topics = [
            SmartCollectionSuggestions.Suggestion(name: "Flight", itemIDs: trip.map(\.id), keyTerms: ["flight"]),
            SmartCollectionSuggestions.Suggestion(name: "Invoice", itemIDs: mixed.map(\.id), keyTerms: ["invoice"]),
            SmartCollectionSuggestions.Suggestion(
                name: "Clipboard Group",
                itemIDs: trip.map(\.id),
                keyTerms: ["flight"]
            )
        ]

        let offered = CollectionSuggester.suggest(clips: history, id: \.id, existing: [], topics: topics)
            .filter { $0.group == .topics }

        #expect(offered.map(\.name) == ["Flight"])
        #expect(offered.first?.matchCount == 5)
    }

    @Test("a topic whose first key term misses is offered through the next term that covers it")
    func whenFirstTermMisses_thenNextTermIsTried() {
        let trip = clips(5) { Clip(previewText: "booking \($0) for the Lisbon flight") }
        let history = trip + clips(30) { Clip(previewText: "filler \($0)") }
        let topics = [
            SmartCollectionSuggestions.Suggestion(
                name: "Booking",
                itemIDs: trip.map(\.id),
                keyTerms: ["reservation", "flight"]
            )
        ]

        let offered = CollectionSuggester.suggest(clips: history, id: \.id, existing: [], topics: topics)
            .filter { $0.group == .topics }

        #expect(offered.count == 1)
        #expect(offered.first?.matchCount == 5)
    }

    @Test("two topics that end up on the same term are offered once")
    func whenTwoTopicsShareATerm_thenOneSuggestion() {
        let trip = clips(5) { Clip(previewText: "flight \($0)") }
        let history = trip + clips(30) { Clip(previewText: "filler \($0)") }
        let topics = [
            SmartCollectionSuggestions.Suggestion(name: "Flight", itemIDs: trip.map(\.id), keyTerms: ["flight"]),
            SmartCollectionSuggestions.Suggestion(name: "Flight & Seat", itemIDs: trip.map(\.id), keyTerms: ["flight"])
        ]

        let offered = CollectionSuggester.suggest(clips: history, id: \.id, existing: [], topics: topics)
            .filter { $0.group == .topics }

        #expect(offered.count == 1)
    }

    @Test("a topic cluster whose members split across two key terms is offered with an OR rule")
    func whenSingleTermMissesButPairCovers_thenMultiTermTopicOffered() {
        let cluster = [
            Clip(previewText: "docker build -t app ."),
            Clip(previewText: "docker compose up -d"),
            Clip(previewText: "kubectl get pods"),
            Clip(previewText: "kubectl logs deploy/api"),
            Clip(previewText: "helm upgrade release")
        ]
        let history = cluster + clips(30) { Clip(previewText: "filler \($0)") }
        let topics = [
            SmartCollectionSuggestions.Suggestion(
                name: "Docker & Kubectl",
                itemIDs: cluster.map(\.id),
                keyTerms: ["docker", "kubectl", "helm"]
            )
        ]

        let offered = CollectionSuggester.suggest(clips: history, id: \.id, existing: [], topics: topics)
            .filter { $0.group == .topics }

        #expect(offered.count == 1)
        #expect(offered.first?.name == "Docker & Kubectl")
        #expect(offered.first?.matchCount == 5)
    }
}
