// SPDX-License-Identifier: MIT
import Foundation
import Synchronization
import Testing
@testable import Pesto

@Suite("Preference changes are reacted to once per burst")
@MainActor
struct DefaultsChangeObserverTests {
    @Test("fifty writes in a row cause one run, after the last of them")
    func whenManyWritesArrive_thenOneRunFollows() async throws {
        let runs = Mutex(0)
        let observer = DefaultsChangeObserver(delay: .milliseconds(60)) { runs.withLock { $0 += 1 } }
        let defaults = ThrowawayDefaults.make()

        for index in 0..<50 {
            defaults.set(index, forKey: "slider")
        }
        #expect(runs.withLock { $0 } == 0, "it reacted before the burst ended")
        try await Task.sleep(for: .milliseconds(400))

        #expect(runs.withLock { $0 } == 1)
        withExtendedLifetime(observer) {}
    }

    @Test("a write after a pause starts another run")
    func whenAWriteFollowsAPause_thenItRunsAgain() async throws {
        let runs = Mutex(0)
        let observer = DefaultsChangeObserver(delay: .milliseconds(40)) { runs.withLock { $0 += 1 } }
        let defaults = ThrowawayDefaults.make()

        defaults.set(1, forKey: "a")
        try await Task.sleep(for: .milliseconds(300))
        defaults.set(2, forKey: "a")
        try await Task.sleep(for: .milliseconds(300))

        #expect(runs.withLock { $0 } == 2)
        withExtendedLifetime(observer) {}
    }
}
