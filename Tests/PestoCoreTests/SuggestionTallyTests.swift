// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("What the command bar suggests from a history")
struct SuggestionTallyTests {
    @Test("the most used come first, up to the limit")
    func whenRanked_thenMostUsedFirstAndLimited() {
        let ranked = TopCounts.rank(["a": 1, "b": 5, "c": 3, "d": 2], limit: 3)
        #expect(ranked == ["b", "c", "d"])
    }

    @Test("equal counts are ordered by name, so the chips never shuffle between refreshes")
    func whenCountsTie_thenAlphabetical() {
        #expect(TopCounts.rank(["zeta": 2, "alpha": 2, "mid": 2], limit: 2) == ["alpha", "mid"])
    }

    @Test("a zero or negative limit and an empty history give nothing")
    func whenNothingToRank_thenEmpty() {
        #expect(TopCounts.rank(["a": 1], limit: 0).isEmpty)
        #expect(TopCounts.rank(["a": 1], limit: -3).isEmpty)
        #expect(TopCounts.rank([String: Int](), limit: 5).isEmpty)
    }

    @Test("tags are counted across clips and apps by bundle id")
    func whenClipsAreAdded_thenTagsAndAppsAreCounted() {
        var tally = SuggestionTally()
        tally.add(tags: ["work", "ops"], bundleID: "com.apple.Notes", appName: "Notes")
        tally.add(tags: ["work"], bundleID: "com.apple.Notes", appName: "Notes")
        tally.add(tags: [], bundleID: "com.apple.Safari", appName: "Safari")
        tally.add(tags: ["ops", "work"], bundleID: nil, appName: nil)

        let result = tally.suggestions(tagLimit: 8, appLimit: 5)

        #expect(result.topTags == ["work", "ops"])
        #expect(result.topApps == [
            SourceApp(bundleID: "com.apple.Notes", name: "Notes"),
            SourceApp(bundleID: "com.apple.Safari", name: "Safari")
        ])
    }

    @Test("an app is named as the first clip seen names it, which is the newest when clips are added newest first")
    func whenAppRenamed_thenFirstNameSeenWins() {
        var tally = SuggestionTally()
        tally.add(tags: [], bundleID: "com.example.app", appName: "New Name")
        tally.add(tags: [], bundleID: "com.example.app", appName: "Old Name")

        #expect(tally.suggestions(tagLimit: 1, appLimit: 1).topApps.first?.name == "New Name")
    }

    @Test("an app with a bundle id but no name is left out, as the filter chip needs a label")
    func whenAppHasNoName_thenSkipped() {
        var tally = SuggestionTally()
        tally.add(tags: [], bundleID: "com.example.nameless", appName: nil)
        tally.add(tags: [], bundleID: "com.example.named", appName: "Named")

        #expect(tally.suggestions(tagLimit: 1, appLimit: 5).topApps.map(\.bundleID) == ["com.example.named"])
    }

    @Test("a clip copied on another device is noticed, and a history of local clips has none")
    func whenRemoteClipAdded_thenHasRemoteClips() {
        var tally = SuggestionTally()
        tally.add(tags: [], bundleID: "com.apple.Notes", appName: "Notes")
        #expect(tally.suggestions(tagLimit: 8, appLimit: 5).hasRemoteClips == false)

        tally.add(tags: [], bundleID: nil, appName: nil, isRemote: true)
        #expect(tally.suggestions(tagLimit: 8, appLimit: 5).hasRemoteClips)
    }
}
