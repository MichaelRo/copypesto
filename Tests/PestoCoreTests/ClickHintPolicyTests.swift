// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("ClickHintPolicy")
struct ClickHintPolicyTests {
    @Test("a first single click that only focuses shows the hint")
    func whenFirstFocusClick_thenShows() {
        #expect(ClickHintPolicy.shouldShow(timesShown: 0, hasDoubleClickPasted: false, tap: .focus))
    }

    @Test("it stops after three times")
    func whenShownThreeTimes_thenNever() {
        #expect(ClickHintPolicy.shouldShow(timesShown: 2, hasDoubleClickPasted: false, tap: .focus))
        #expect(!ClickHintPolicy.shouldShow(timesShown: 3, hasDoubleClickPasted: false, tap: .focus))
    }

    @Test("someone who has double-clicked a paste never sees it")
    func whenDoubleClickPasted_thenNever() {
        #expect(!ClickHintPolicy.shouldShow(timesShown: 0, hasDoubleClickPasted: true, tap: .focus))
    }

    @Test("only a click that does nothing but focus earns the hint")
    func whenTapPastesOrSelects_thenNever() {
        for tap in [ShelfTap.paste, .copy, .toggleSelection, .ignore] {
            #expect(!ClickHintPolicy.shouldShow(timesShown: 0, hasDoubleClickPasted: false, tap: tap))
        }
    }

    @Test("a double-click paste is recognised")
    func whenDoubleClickRoutesToPaste_thenCounts() {
        #expect(ClickHintPolicy.isDoubleClickPaste(click: .double, tap: .paste))
        #expect(!ClickHintPolicy.isDoubleClickPaste(click: .activate, tap: .paste))
        #expect(!ClickHintPolicy.isDoubleClickPaste(click: .double, tap: .ignore))
    }

    @Test("the keys are this Mac's own state")
    func whenKeysDeclared_thenRegistered() {
        #expect(Setting.clickHintShownCount.defaultValue == 0)
        #expect(Setting.doubleClickPasted.defaultValue == false)
        #expect(Setting.allNames.contains(Setting.clickHintShownCount.name))
        #expect(Setting.allNames.contains(Setting.doubleClickPasted.name))
    }
}
