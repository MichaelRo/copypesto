// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The last update check line")
struct UpdateCheckCaptionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let english = Locale(identifier: "en_US")

    @Test("a Mac that never checked says so")
    func whenNeverChecked_thenItSaysSo() {
        #expect(UpdateCheckCaption.text(lastCheck: nil, now: now, locale: english) == "Not checked yet.")
    }

    @Test("a check from a few hours ago reads as relative time")
    func whenCheckedHoursAgo_thenItIsRelative() {
        let text = UpdateCheckCaption.text(lastCheck: now.addingTimeInterval(-3 * 3600), now: now, locale: english)

        #expect(text == "Last checked 3 hours ago.")
    }

    @Test("a check a moment ago does not claim a time in the future")
    func whenCheckedJustNow_thenItIsNotInTheFuture() {
        let text = UpdateCheckCaption.text(lastCheck: now.addingTimeInterval(5), now: now, locale: english)

        #expect(text == "Last checked just now.")
    }
}
