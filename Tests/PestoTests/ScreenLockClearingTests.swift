// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import Pesto

/// Uses a private notification centre and name, so the real distributed "screen is locked" notification (which other
/// apps listen to) is never posted from a test.
@Suite("Clear history when the screen locks", .serialized)
@MainActor
struct ScreenLockClearingTests {
    private let center = NotificationCenter()
    private let name = Notification.Name("io.pesto.tests.screenLocked.\(UUID().uuidString)")

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var times: Int {
            lock.withLock { value }
        }

        func increment() {
            lock.withLock { value += 1 }
        }
    }

    private func waitForCount(_ counter: Counter, _ expected: Int) async {
        for _ in 0..<50 where counter.times < expected {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("with the setting on, locking the screen clears history once per lock")
    func whenEnabled_thenClearsOnEachLock() async {
        let counter = Counter()
        let clearing = ScreenLockClearing(
            center: center,
            name: name,
            isEnabled: { true },
            clear: { counter.increment() }
        )

        center.post(name: name, object: nil)
        await waitForCount(counter, 1)
        center.post(name: name, object: nil)
        await waitForCount(counter, 2)

        #expect(counter.times == 2)
        clearing.stop()
    }

    @Test("with the setting off, locking the screen leaves history alone")
    func whenDisabled_thenNothingCleared() async {
        let counter = Counter()
        let clearing = ScreenLockClearing(
            center: center,
            name: name,
            isEnabled: { false },
            clear: { counter.increment() }
        )

        center.post(name: name, object: nil)
        try? await Task.sleep(for: .milliseconds(300))

        #expect(counter.times == 0)
        clearing.stop()
    }

    @Test("the setting is read at the moment of the lock, not when the observer was created")
    func whenSettingChanges_thenLatestValueUsed() async {
        let counter = Counter()
        let enabled = Counter()
        let clearing = ScreenLockClearing(center: center, name: name, isEnabled: { enabled.times > 0 }, clear: {
            counter.increment()
        })

        center.post(name: name, object: nil)
        try? await Task.sleep(for: .milliseconds(200))
        enabled.increment()
        center.post(name: name, object: nil)
        await waitForCount(counter, 1)

        #expect(counter.times == 1)
        clearing.stop()
    }

    @Test("after stop, locks are ignored")
    func whenStopped_thenNothingCleared() async {
        let counter = Counter()
        let clearing = ScreenLockClearing(
            center: center,
            name: name,
            isEnabled: { true },
            clear: { counter.increment() }
        )
        clearing.stop()

        center.post(name: name, object: nil)
        try? await Task.sleep(for: .milliseconds(300))

        #expect(counter.times == 0)
    }
}
