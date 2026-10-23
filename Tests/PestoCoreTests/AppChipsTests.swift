// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The app chips on the shelf")
struct AppChipsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 8_000_000)
    private let notes = SourceApp(bundleID: "com.apple.Notes", name: "Notes")
    private let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
    private let mail = SourceApp(bundleID: "com.apple.mail", name: "Mail")
    private let slack = SourceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    private let pesto = SourceApp(bundleID: "net.copypesto.pesto", name: "Pesto")

    @Test("only clips from the last seven days make an app recent, most copied first")
    func whenCountingRecentApps_thenOnlyTheWindowCounts() {
        var tally = SuggestionTally(recentSince: now.addingTimeInterval(-7 * 86_400))
        for _ in 0..<5 {
            tally.add(
                tags: [],
                bundleID: safari.bundleID,
                appName: "Safari",
                timestamp: now.addingTimeInterval(-10 * 86_400)
            )
        }
        tally.add(tags: [], bundleID: notes.bundleID, appName: "Notes", timestamp: now.addingTimeInterval(-86_400))
        tally.add(tags: [], bundleID: notes.bundleID, appName: "Notes", timestamp: now.addingTimeInterval(-2 * 86_400))
        tally.add(tags: [], bundleID: mail.bundleID, appName: "Mail", timestamp: now.addingTimeInterval(-3 * 86_400))

        let result = tally.suggestions(tagLimit: 0, appLimit: 5, recentAppLimit: 6)

        #expect(result.recentApps == [notes, mail])
        #expect(result.topApps.first == safari, "the all-time list is unchanged")
    }

    @Test("with no window there are no recent apps")
    func whenNoWindow_thenNone() {
        var tally = SuggestionTally()
        tally.add(tags: [], bundleID: notes.bundleID, appName: "Notes", timestamp: now)

        #expect(tally.suggestions(tagLimit: 0, appLimit: 5, recentAppLimit: 6).recentApps.isEmpty)
    }

    @Test("the frontmost app comes first, then up to three recent apps without repeating it")
    func whenChoosingChips_thenFrontmostThenThreeRecent() {
        let chips = AppChips.chips(
            frontmost: notes, recent: [safari, notes, mail, slack, pesto], ownBundleID: pesto.bundleID
        )

        #expect(chips == [notes, safari, mail, slack])
    }

    @Test("Pesto is never a chip, even when it is in front")
    func whenPestoIsFrontmost_thenNoFrontmostChip() {
        let chips = AppChips.chips(frontmost: pesto, recent: [pesto, safari], ownBundleID: pesto.bundleID)

        #expect(chips == [safari])
    }

    @Test("with nothing in front the recent apps still show")
    func whenNothingFrontmost_thenRecentOnly() {
        #expect(AppChips.chips(frontmost: nil, recent: [safari], ownBundleID: pesto.bundleID) == [safari])
    }

    @Test("with no app in front a fourth recent app fills the row")
    func whenNoFrontmost_thenAFourthRecentAppStandsIn() {
        let chips = AppChips.chips(
            frontmost: nil,
            recent: [notes, safari, mail, slack, pesto],
            ownBundleID: pesto.bundleID
        )
        #expect(chips == [notes, safari, mail, slack])
        let withFront = AppChips.chips(
            frontmost: notes,
            recent: [safari, mail, slack, pesto],
            ownBundleID: pesto.bundleID
        )
        #expect(withFront == [notes, safari, mail, slack])
    }
}
