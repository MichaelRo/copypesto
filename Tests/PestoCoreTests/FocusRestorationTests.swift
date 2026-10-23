// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("FocusRestoration")
@MainActor
struct FocusRestorationTests {
    @Test("whenCaptured_thenClearNilsTarget")
    func whenCaptured_thenClearNilsTarget() async {
        let restoration = FocusRestoration()
        // capture() stores whatever is frontmost (may be the test runner itself).
        restoration.capture()
        restoration.clear()
        // After clear, capturedTarget is nil; activate() must return false.
        let activated = await restoration.activate()
        #expect(activated == false)
    }

    @Test("whenNeverCaptured_thenActivateReturnsFalse")
    func whenNeverCaptured_thenActivateReturnsFalse() async {
        let restoration = FocusRestoration()
        let activated = await restoration.activate()
        #expect(activated == false)
    }

    private func anotherApp() throws -> NSRunningApplication {
        try #require(NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
        })
    }

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSinceReferenceDate: 1000)
    }

    private final class Frontmost: @unchecked Sendable {
        var application: NSRunningApplication
        init(_ application: NSRunningApplication) {
            self.application = application
        }
    }

    @Test("Pesto itself is never the paste target, so a paste cannot land in Pesto's own field")
    func whenPestoIsFrontmost_thenNothingIsCaptured() throws {
        let pesto = try anotherApp()
        let restoration = FocusRestoration(
            frontmostApplication: { pesto }, ownProcessIdentifier: pesto.processIdentifier
        )

        restoration.capture()

        #expect(restoration.capturedTarget == nil)
    }

    @Test("a capture that was long ago but whose shelf was open until now is not stale")
    func whenTheShelfWasOpenLong_thenHidingRefreshesTheCapture() throws {
        let clock = Clock()
        let other = try anotherApp()
        let restoration = FocusRestoration(frontmostApplication: { other }, now: { clock.now })
        restoration.capture()

        clock.now.addTimeInterval(60)
        #expect(restoration.isStale, "without a refresh the 15 second deadline has long passed")
        restoration.markHidden()

        #expect(!restoration.isStale)
    }

    @Test("a paste from a window of Pesto's own keeps the app the person was in and counts from now")
    func whenPestoIsFrontmost_thenTheEarlierTargetIsKeptAndRefreshed() throws {
        let clock = Clock()
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let target = try #require(apps.first)
        let pesto = try #require(apps.first { $0.processIdentifier != target.processIdentifier })
        let front = Frontmost(target)
        let restoration = FocusRestoration(
            frontmostApplication: { front.application }, now: { clock.now },
            ownProcessIdentifier: pesto.processIdentifier
        )
        restoration.capture()
        clock.now.addTimeInterval(60)
        front.application = pesto

        restoration.captureKeepingTargetWhenPestoIsFront()

        #expect(restoration.capturedTarget?.processIdentifier == target.processIdentifier)
        #expect(!restoration.isStale)
    }

    @Test("a paste from a window that is not Pesto's captures whoever is in front")
    func whenAnotherAppIsFrontmost_thenItIsCaptured() throws {
        let other = try anotherApp()
        let restoration = FocusRestoration(frontmostApplication: { other }, ownProcessIdentifier: -1)

        restoration.captureKeepingTargetWhenPestoIsFront()

        #expect(restoration.capturedTarget?.processIdentifier == other.processIdentifier)
    }

    @Test("a capture that is stale when the paste starts is refused")
    func whenStale_thenActivateIsRefusedAndTheTargetDropped() async throws {
        let clock = Clock()
        let other = try anotherApp()
        let restoration = FocusRestoration(frontmostApplication: { other }, now: { clock.now })
        restoration.capture()
        clock.now.addTimeInterval(60)

        #expect(await restoration.activate() == false)
        #expect(restoration.capturedTarget == nil)
    }

    @Test("an activation announced on the workspace's own notification center is seen")
    func whenTheWorkspaceAnnouncesActivation_thenItIsConfirmed() async throws {
        let center = NotificationCenter()
        let other = try anotherApp()
        let restoration = FocusRestoration(frontmostApplication: { nil }, workspaceCenter: center)
        let confirmation = restoration.makeActivationConfirmation(pid: other.processIdentifier)

        center.post(
            name: NSWorkspace.didActivateApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: other]
        )

        #expect(await restoration.awaitActivation(
            confirmation: confirmation, pid: other.processIdentifier, timeout: .seconds(2)
        ))
    }

    @Test("when no notification arrives but the target has come to the front, the timeout still succeeds")
    func whenTheTargetIsFrontAfterTheTimeout_thenItCounts() async throws {
        let other = try anotherApp()
        let restoration = FocusRestoration(frontmostApplication: { other }, workspaceCenter: NotificationCenter())
        let confirmation = restoration.makeActivationConfirmation(pid: other.processIdentifier)

        #expect(await restoration.awaitActivation(
            confirmation: confirmation, pid: other.processIdentifier, timeout: .milliseconds(50)
        ))
    }

    @Test("when nothing confirms the activation, it is reported as failed")
    func whenNothingConfirms_thenFailed() async throws {
        let other = try anotherApp()
        let restoration = FocusRestoration(frontmostApplication: { nil }, workspaceCenter: NotificationCenter())
        let confirmation = restoration.makeActivationConfirmation(pid: other.processIdentifier)

        #expect(await restoration.awaitActivation(
            confirmation: confirmation, pid: other.processIdentifier, timeout: .milliseconds(50)
        ) == false)
    }

    // MARK: - Waiting for the keystroke to have somewhere to go

    private final class ScriptedProbe: KeyboardFocusProbing, @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [pid_t?]
        private(set) var asked = 0

        init(_ answers: [pid_t?]) {
            self.answers = answers
        }

        func focusedProcess() -> pid_t? {
            lock.withLock {
                asked += 1
                return answers.count > 1 ? answers.removeFirst() : answers.first.flatMap(\.self)
            }
        }
    }

    @Test("the wait ends as soon as the system says the target would receive a keystroke")
    func whenTheTargetTakesTheKeyboard_thenTheWaitEndsEarly() async {
        let probe = ScriptedProbe([nil, 999, 4242])
        let restoration = FocusRestoration(focusProbe: probe, pollInterval: .milliseconds(1))

        await restoration.waitForKeyboardFocus(of: 4242, ceiling: .seconds(30))

        #expect(probe.asked == 3)
    }

    @Test("when the system never says, the wait runs to its ceiling, as the fixed sleep did")
    func whenTheSystemNeverSays_thenTheCeilingApplies() async {
        let probe = ScriptedProbe([nil])
        let restoration = FocusRestoration(focusProbe: probe, pollInterval: .milliseconds(5))
        let clock = ContinuousClock()

        let waited = await clock.measure { await restoration.waitForKeyboardFocus(of: 1, ceiling: .milliseconds(120)) }

        #expect(waited >= .milliseconds(110))
        #expect(waited < .seconds(10))
    }

    @Test("a cancelled wait returns at once")
    func whenCancelled_thenTheWaitReturns() async {
        let probe = ScriptedProbe([nil])
        let restoration = FocusRestoration(focusProbe: probe, pollInterval: .milliseconds(5))
        let clock = ContinuousClock()
        let task = Task { @MainActor in await restoration.waitForKeyboardFocus(of: 1, ceiling: .seconds(30)) }
        task.cancel()

        let waited = await clock.measure { await task.value }

        #expect(waited < .seconds(2))
    }
}
