// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("HotkeyController and StackPasteSession")
@MainActor
struct HotkeyAndStackSessionTests {
    @Test("GlobalHotkeySuspension nests and unregisters only on the first begin and resumes only on the last end")
    func whenSuspensionNests_thenOnlyOuterEdgesTransition() {
        var suspension = GlobalHotkeySuspension()
        #expect(!suspension.isSuspended)
        let firstBegin = suspension.begin()
        #expect(firstBegin)
        #expect(suspension.isSuspended)
        let secondBegin = suspension.begin()
        #expect(!secondBegin)
        #expect(suspension.isSuspended)
        let firstEnd = suspension.end()
        #expect(!firstEnd)
        #expect(suspension.isSuspended)
        let secondEnd = suspension.end()
        #expect(secondEnd)
        #expect(!suspension.isSuspended)
        let extraEnd = suspension.end()
        #expect(!extraEnd)
    }

    @Test("HotkeyController starts with no conflicts or unavailable slots and tears down cleanly")
    func whenHotkeyControllerIsCreated_thenStateIsCleanAndSuspendResumeAreSafe() {
        let controller = HotkeyController()
        #expect(controller.conflictingHotkeys.isEmpty)
        #expect(controller.unavailableSlots.isEmpty)
        #expect(controller.systemTakenSlots.isEmpty)
        controller.suspend()
        controller.resume()
        controller.unregister()
        #expect(controller.conflictingHotkeys.isEmpty)
    }

    @Test("StackPasteSession tracks watching state, cancels pending preparation on stop, and runs scheduled work")
    func whenStackPasteSessionWatchesAndPrepares_thenLifecycleIsManaged() async throws {
        let session = StackPasteSession()
        #expect(!session.isWatching)

        session.watch {}
        #expect(session.isWatching)

        var ranFirst = false
        session.prepare(after: .milliseconds(200)) {
            ranFirst = true
        }
        session.stop()
        #expect(!session.isWatching)

        try await Task.sleep(for: .milliseconds(250))
        #expect(!ranFirst)

        var ranSecond = false
        session.prepare(after: .milliseconds(20)) {
            ranSecond = true
        }
        try await Task.sleep(for: .milliseconds(80))
        #expect(ranSecond)
        session.stop()
    }
}
