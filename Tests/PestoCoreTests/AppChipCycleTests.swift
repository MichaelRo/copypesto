// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("App chip cycle")
struct AppChipCycleTests {
    private let chips = ["a", "b", "c"]

    @Test("forward from no filter picks the first chip, backward the last")
    func whenNothingSelected_thenEdgeChip() {
        #expect(AppChipCycle.next(current: [], chips: chips, forward: true) == ["a"])
        #expect(AppChipCycle.next(current: [], chips: chips, forward: false) == ["c"])
    }

    @Test("forward steps down the row and past the last chip clears the filter")
    func whenForward_thenNextThenAll() {
        #expect(AppChipCycle.next(current: ["a"], chips: chips, forward: true) == ["b"])
        #expect(AppChipCycle.next(current: ["b"], chips: chips, forward: true) == ["c"])
        #expect(AppChipCycle.next(current: ["c"], chips: chips, forward: true) == [])
    }

    @Test("backward steps up the row and past the first chip clears the filter")
    func whenBackward_thenPreviousThenAll() {
        #expect(AppChipCycle.next(current: ["c"], chips: chips, forward: false) == ["b"])
        #expect(AppChipCycle.next(current: ["b"], chips: chips, forward: false) == ["a"])
        #expect(AppChipCycle.next(current: ["a"], chips: chips, forward: false) == [])
    }

    @Test("with several chips on, forward goes after the last of them and backward before the first")
    func whenSeveralSelected_thenFromTheEdgeInTheDirection() {
        #expect(AppChipCycle.next(current: ["a", "b"], chips: chips, forward: true) == ["c"])
        #expect(AppChipCycle.next(current: ["b", "c"], chips: chips, forward: true) == [])
        #expect(AppChipCycle.next(current: ["b", "c"], chips: chips, forward: false) == ["a"])
        #expect(AppChipCycle.next(current: ["a", "c"], chips: chips, forward: false) == [])
    }

    @Test("an app no longer on the row is ignored, and a filter of only such apps starts over")
    func whenSelectionNotOnRow_thenIgnoredOrRestarted() {
        #expect(AppChipCycle.next(current: ["a", "gone"], chips: chips, forward: true) == ["b"])
        #expect(AppChipCycle.next(current: ["gone"], chips: chips, forward: true) == ["a"])
        #expect(AppChipCycle.next(current: ["gone"], chips: chips, forward: false) == ["c"])
    }

    @Test("with no chips there is nothing to select")
    func whenNoChips_thenEmpty() {
        #expect(AppChipCycle.next(current: [], chips: [], forward: true) == [])
        #expect(AppChipCycle.next(current: ["gone"], chips: [], forward: false) == [])
    }

    @Test("a single chip toggles on and off")
    func whenOneChip_thenToggles() {
        #expect(AppChipCycle.next(current: [], chips: ["a"], forward: true) == ["a"])
        #expect(AppChipCycle.next(current: ["a"], chips: ["a"], forward: true) == [])
        #expect(AppChipCycle.next(current: ["a"], chips: ["a"], forward: false) == [])
    }
}
