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

    @Test("every named app is listed with its count, most copied first, ties by name")
    func whenManyApps_thenAllAppsListedWithCounts() {
        var tally = SuggestionTally()
        for _ in 0..<3 {
            tally.add(tags: [], bundleID: "com.b", appName: "Beta")
        }
        for _ in 0..<3 {
            tally.add(tags: [], bundleID: "com.a", appName: "Alpha")
        }
        tally.add(tags: [], bundleID: "com.c", appName: "Gamma")

        let result = tally.suggestions(tagLimit: 1, appLimit: 1)

        #expect(result.allApps.map(\.name) == ["Alpha", "Beta", "Gamma"])
        #expect(result.allApps.map(\.count) == [3, 3, 1])
        #expect(result.topApps.count == 1)
    }

    @Test("languages are counted across clips, the two with their own chips and plain text left out")
    func whenClipsHaveLanguages_thenCountedWithoutMarkdownJSONOrText() {
        var tally = SuggestionTally()
        tally.add(tags: [], bundleID: nil, appName: nil, language: "python")
        tally.add(tags: [], bundleID: nil, appName: nil, language: "python")
        tally.add(tags: [], bundleID: nil, appName: nil, language: "swift")
        tally.add(tags: [], bundleID: nil, appName: nil, language: "markdown")
        tally.add(tags: [], bundleID: nil, appName: nil, language: "json")
        tally.add(tags: [], bundleID: nil, appName: nil, language: "text")
        tally.add(tags: [], bundleID: nil, appName: nil, language: nil)

        let languages = tally.suggestions(tagLimit: 1, appLimit: 1).languages

        #expect(languages == [LanguageCount(name: "python", count: 2), LanguageCount(name: "swift", count: 1)])
    }

    @Test("a language is shown the way people write it")
    func whenLanguageNamed_thenDisplayNameIsReadable() {
        #expect(LanguageCount(name: "javascript", count: 1).displayName == "JavaScript")
        #expect(LanguageCount(name: "html", count: 1).displayName == "HTML")
        #expect(LanguageCount(name: "sql", count: 1).displayName == "SQL")
        #expect(LanguageCount(name: "python", count: 1).displayName == "Python")
        #expect(LanguageCount(name: "go", count: 1).displayName == "Go")
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
