// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Activity gate")
struct ActivityGateTests {
    private let quiet = Duration.milliseconds(80)

    @Test("with no recent activity, waiting returns at once")
    func whenNothingHappened_thenWaitReturnsImmediately() async {
        let gate = ActivityGate(quietPeriod: quiet)
        let started = ContinuousClock.now
        await gate.waitUntilQuiet()
        #expect(ContinuousClock.now - started < .milliseconds(40))
    }

    @Test("after activity, waiting lasts until the quiet period has passed")
    func whenActivityJustHappened_thenWaitLastsTheQuietPeriod() async {
        let gate = ActivityGate(quietPeriod: quiet)
        gate.noteActivity()
        let started = ContinuousClock.now
        await gate.waitUntilQuiet()
        #expect(ContinuousClock.now - started >= .milliseconds(70))
    }

    @Test("activity that keeps coming keeps the wait going")
    func whenActivityRepeats_thenWaitIsExtended() async {
        let gate = ActivityGate(quietPeriod: quiet)
        gate.noteActivity()
        let started = ContinuousClock.now
        async let waiting: Void = gate.waitUntilQuiet()
        for _ in 0..<4 {
            try? await Task.sleep(for: .milliseconds(50))
            gate.noteActivity()
        }
        await waiting
        #expect(ContinuousClock.now - started >= .milliseconds(250))
    }

    @Test("a cancelled wait returns instead of holding its task")
    func whenCancelled_thenWaitReturns() async {
        let gate = ActivityGate(quietPeriod: .seconds(30))
        gate.noteActivity()
        let task = Task { await gate.waitUntilQuiet() }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let started = ContinuousClock.now
        await task.value
        #expect(ContinuousClock.now - started < .seconds(2))
    }
}
