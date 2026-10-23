// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

@Suite("Activity's storage caption")
struct RetentionCaptionTests {
    @Test("the caption describes the retention the person chose, not the default")
    func whenRetentionIsChosen_thenCaptionShowsIt() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(7, forKey: "retentionDays")
        defaults.set(1000, forKey: "retentionMaxItems")

        let caption = RetentionCaption.text(for: RetentionPolicy.fromDefaults(defaults))

        #expect(caption.contains("7 days"))
        #expect(caption.contains("1,000 clips"))
        #expect(!caption.contains("30 days"))
        #expect(!caption.contains("5,000"))
    }

    @Test("keeping clips forever names no day count")
    func whenRetentionIsForever_thenNoDayCount() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(RetentionChoices.foreverDays, forKey: "retentionDays")

        let caption = RetentionCaption.text(for: RetentionPolicy.fromDefaults(defaults))

        #expect(!caption.contains("day"))
        #expect(caption.contains("5,000 clips"))
    }

    @Test("one day reads in the singular")
    func whenOneDay_thenSingular() {
        let policy = RetentionPolicy(maxAge: 86_400, maxItemCount: 100, maxTotalBytes: 2 * 1024 * 1024 * 1024)

        #expect(RetentionCaption.text(for: policy).contains("1 day,"))
    }
}
