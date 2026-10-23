// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("ClearRange")
struct ClearRangeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    /// 2026-09-24 15:30:00 UTC
    private let now = Date(timeIntervalSince1970: 1_790_263_800)

    @Test("the time ranges start that long before now")
    func timeRanges_startBeforeNow() {
        #expect(ClearRange.lastFiveMinutes.start(now: now, calendar: calendar) == now.addingTimeInterval(-300))
        #expect(ClearRange.lastHour.start(now: now, calendar: calendar) == now.addingTimeInterval(-3600))
    }

    @Test("today starts at midnight in the given calendar")
    func today_startsAtMidnight() {
        let start = ClearRange.today.start(now: now, calendar: calendar)
        #expect(start == calendar.startOfDay(for: now))
        #expect(start.map { calendar.component(.hour, from: $0) } == 0)
    }

    @Test("all has no start, so it covers the whole history")
    func all_hasNoStart() {
        #expect(ClearRange.all.start(now: now, calendar: calendar) == nil)
    }

    @Test("automation names map to ranges")
    func automationNames_mapToRanges() {
        #expect(ClearRange(automationName: "hour") == .lastHour)
        #expect(ClearRange(automationName: "today") == .today)
        #expect(ClearRange(automationName: "all") == .all)
    }

    @Test("an unknown or missing automation name is not a range, so nothing is cleared")
    func unknownAutomationName_isNil() {
        #expect(ClearRange(automationName: nil) == nil)
        #expect(ClearRange(automationName: "") == nil)
        #expect(ClearRange(automationName: "yesterday") == nil)
    }

    @Test("every range has a description for the confirmation")
    func everyRange_hasDescription() {
        for range in ClearRange.allCases {
            #expect(!range.summary.isEmpty)
        }
    }
}
