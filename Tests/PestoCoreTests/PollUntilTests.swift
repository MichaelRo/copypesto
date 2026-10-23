// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("PollUntil")
struct PollUntilTests {
    @Test("a condition that is already true returns at once")
    @MainActor
    func whenAlreadyTrue_thenImmediately() async {
        let result = await PollUntil.holds(timeout: .seconds(5), interval: .milliseconds(10)) { true }

        #expect(result)
    }

    @Test("a condition that turns true within the timeout is waited for")
    @MainActor
    func whenTurnsTrue_thenTrue() async {
        var calls = 0

        let result = await PollUntil.holds(timeout: .seconds(5), interval: .milliseconds(5)) {
            calls += 1
            return calls >= 4
        }

        #expect(result)
        #expect(calls == 4)
    }

    @Test("a condition that never holds gives up after the timeout")
    @MainActor
    func whenNeverTrue_thenFalse() async {
        let result = await PollUntil.holds(timeout: .milliseconds(60), interval: .milliseconds(10)) { false }

        #expect(!result)
    }
}
