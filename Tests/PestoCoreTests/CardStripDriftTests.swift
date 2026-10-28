// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("CardStripDrift")
struct CardStripDriftTests {
    private func run(_ drift: inout CardStripDrift, seconds: Double, farthest: CGFloat = 1000) {
        var elapsed = 0.0
        while elapsed < seconds {
            drift.advance(by: 1.0 / 60, farthest: farthest)
            elapsed += 1.0 / 60
        }
    }

    @Test("the row never moves faster than the cruising pace")
    func whenAdvancing_thenSpeedStaysUnderTheCap() {
        var drift = CardStripDrift(offset: 400)
        var fastest: CGFloat = 0
        for _ in 0..<600 {
            let before = drift.offset
            drift.advance(by: 1.0 / 60, farthest: 1000)
            fastest = max(fastest, abs(drift.offset - before) * 60)
        }

        #expect(fastest <= CardStripDrift.cruiseSpeed + 0.01)
    }

    @Test("starting or resuming eases in instead of jumping to full pace")
    func whenResumed_thenTheFirstStepsAreSlow() {
        var drift = CardStripDrift(offset: 400)
        run(&drift, seconds: 3)
        drift.pause()
        let before = drift.offset

        drift.advance(by: 1.0 / 60, farthest: 1000)

        #expect(abs(drift.offset - before) * 60 < CardStripDrift.cruiseSpeed * 0.2)
    }

    @Test("after the pointer leaves, the row keeps going the way it was going")
    func whenPausedAndResumed_thenDirectionIsKept() {
        var drift = CardStripDrift(offset: 900)
        run(&drift, seconds: 20, farthest: 1000)
        #expect(!drift.movesForward)
        let turnedAt = drift.offset

        drift.pause()
        drift.place(at: turnedAt)
        run(&drift, seconds: 1, farthest: 1000)

        #expect(drift.offset < turnedAt)
        #expect(!drift.movesForward)
    }

    @Test("after a hand scroll it carries on the way the person scrolled")
    func whenTurned_thenItMovesThatWay() {
        var drift = CardStripDrift(offset: 500)

        drift.turn(forward: false)
        run(&drift, seconds: 1, farthest: 1000)
        #expect(drift.offset < 500)

        drift.turn(forward: true)
        let before = drift.offset
        run(&drift, seconds: 1, farthest: 1000)
        #expect(drift.offset > before)
    }

    @Test("it slows toward either end, waits there, and turns around")
    func whenReachingAnEnd_thenItTurnsAfterAPause() {
        var drift = CardStripDrift(offset: 990)
        while drift.movesForward {
            drift.advance(by: 1.0 / 60, farthest: 1000)
        }
        #expect(drift.offset == 1000)

        run(&drift, seconds: CardStripDrift.endPauseSeconds / 2, farthest: 1000)
        #expect(drift.offset == 1000)

        run(&drift, seconds: CardStripDrift.endPauseSeconds + 1, farthest: 1000)
        #expect(drift.offset < 1000)
    }

    @Test("a row too short to scroll stays put")
    func whenNothingToScroll_thenOffsetIsZero() {
        var drift = CardStripDrift(offset: 0)

        run(&drift, seconds: 2, farthest: 0)

        #expect(drift.offset == 0)
    }

    @Test("placing the row where the person left it keeps it inside the scrollable range")
    func whenPlacedOutsideRange_thenClamped() {
        var drift = CardStripDrift(offset: 0)

        drift.place(at: 5000, farthest: 300)

        #expect(drift.offset == 300)
    }
}
