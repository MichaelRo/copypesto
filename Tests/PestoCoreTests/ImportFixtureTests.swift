// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The fixture libraries a UI test imports")
struct ImportFixtureTests {
    private let now = Date(timeIntervalSince1970: 100 * 86_400)

    @Test("Maccy has pins, history of different ages and a skipped entry; Alfred has no pins")
    func whenFixtures_thenTheShapesTheSheetHandles() throws {
        let maccy = try #require(ImportFixture.preview(named: "maccy", now: now))
        let alfred = try #require(ImportFixture.preview(named: "alfred", now: now))
        let paste = try #require(ImportFixture.preview(named: "paste", now: now))

        #expect(maccy.appName == "Maccy")
        #expect(maccy.pinnedCount == 2 && maccy.historyCount == 3 && maccy.skipped == 1)
        #expect(alfred.appName == "Alfred")
        #expect(alfred.pinnedCount == 0 && alfred.historyCount == 3 && alfred.skipped == 2)
        #expect(paste.appName == "Paste")
        #expect(paste.hasPins && paste.historyCount == 3)
    }

    @Test("every fixture has a clip older than the default retention, so the sheet's warning can be seen")
    func whenFixtures_thenSomeHistoryExpires() throws {
        for name in ["maccy", "alfred", "paste"] {
            let preview = try #require(ImportFixture.preview(named: name, now: now))
            #expect(preview.expiring(retention: .default, now: now, includingHistory: true) == 1, "\(name)")
        }
    }

    @Test("an unknown name is no fixture")
    func whenUnknown_thenNil() {
        #expect(ImportFixture.preview(named: "clipy", now: now) == nil)
    }

    @Test("a fixture list names several apps, and each app finds its own library in it")
    func whenList_thenEachAppFindsItsOwn() throws {
        let list = "paste,maccy"
        #expect(ImportFixture.names(in: list) == ["paste", "maccy"])
        #expect(ImportFixture.names(in: nil).isEmpty)
        #expect(try #require(ImportFixture.preview(forApp: "Maccy", in: list, now: now)).appName == "Maccy")
        #expect(try #require(ImportFixture.preview(forApp: "Paste", in: list, now: now)).appName == "Paste")
        #expect(ImportFixture.preview(forApp: "Alfred", in: list, now: now) == nil)
    }
}
