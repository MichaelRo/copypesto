// SPDX-License-Identifier: MIT
import Foundation
import LocalAuthentication
import Testing
@testable import PestoCore

/// The lock never engaged at its default (the timeout preference was unregistered, so it read as 0
/// and 0 meant "unlocked"), and it unlocked itself when no biometric was available.
@Suite("Protected actions while the lock is on")
struct ProtectedActionTests {
    @Test("with the lock off nothing is asked")
    func whenLockOff_thenAllowedWithoutAsking() async {
        let denying = StubUserAuthenticator(available: true, grants: false)

        #expect(await HistoryLockPolicy.permitsProtectedAction(
            lockEnabled: false,
            using: denying,
            reason: "x",
            grace: AuthenticationGrace()
        ))
    }

    @Test("with the lock on the user has to authenticate, and when nothing can authenticate the answer is no")
    func whenLockOn_thenAuthenticationDecides() async {
        let yes = StubUserAuthenticator(available: true, grants: true)
        let no = StubUserAuthenticator(available: true, grants: false)
        let cannot = StubUserAuthenticator(available: false, grants: true)

        #expect(await HistoryLockPolicy.permitsProtectedAction(
            lockEnabled: true,
            using: yes,
            reason: "x",
            grace: AuthenticationGrace()
        ))
        #expect(await !HistoryLockPolicy.permitsProtectedAction(
            lockEnabled: true,
            using: no,
            reason: "x",
            grace: AuthenticationGrace()
        ))
        #expect(await !HistoryLockPolicy.permitsProtectedAction(
            lockEnabled: true,
            using: cannot,
            reason: "x",
            grace: AuthenticationGrace()
        ))
    }
}

@Suite("HistoryLockPolicy")
struct HistoryLockTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("the Touch ID prompt appears by itself only when a locked history is on screen")
    func whenLockedAndVisible_thenPromptsAutomatically() {
        #expect(HistoryLockPolicy.shouldPromptAutomatically(isLocked: true, isVisible: true))
        #expect(!HistoryLockPolicy.shouldPromptAutomatically(isLocked: true, isVisible: false))
        #expect(!HistoryLockPolicy.shouldPromptAutomatically(isLocked: false, isVisible: true))
        #expect(!HistoryLockPolicy.shouldPromptAutomatically(isLocked: false, isVisible: false))
    }

    @Test("the lock does nothing when the user has not turned it on")
    func whenDisabled_thenUnlocked() {
        #expect(!HistoryLockPolicy.isLocked(enabled: false, timeoutMinutes: 5, lastUnlock: nil, now: now))
    }

    @Test("an enabled lock is locked until the first unlock")
    func whenEnabledAndNeverUnlocked_thenLocked() {
        #expect(HistoryLockPolicy.isLocked(enabled: true, timeoutMinutes: 5, lastUnlock: nil, now: now))
    }

    @Test("it stays unlocked within the timeout and locks again after it")
    func whenTimeoutElapses_thenLocksAgain() {
        let twoMinutesAgo = now.addingTimeInterval(-120)
        let sixMinutesAgo = now.addingTimeInterval(-360)
        #expect(!HistoryLockPolicy.isLocked(enabled: true, timeoutMinutes: 5, lastUnlock: twoMinutesAgo, now: now))
        #expect(HistoryLockPolicy.isLocked(enabled: true, timeoutMinutes: 5, lastUnlock: sixMinutesAgo, now: now))
    }

    @Test("a timeout of zero or less is not 'never lock': it falls back to the default and still locks")
    func whenTimeoutMissing_thenDefaultAppliesAndItLocks() {
        #expect(HistoryLockPolicy.isLocked(enabled: true, timeoutMinutes: 0, lastUnlock: nil, now: now))
        let sixMinutesAgo = now.addingTimeInterval(-360)
        #expect(HistoryLockPolicy.isLocked(enabled: true, timeoutMinutes: 0, lastUnlock: sixMinutesAgo, now: now))
        #expect(HistoryLockPolicy.isLocked(enabled: true, timeoutMinutes: -3, lastUnlock: sixMinutesAgo, now: now))
    }

    @Test("unlocking succeeds only when the user authenticates")
    func unlock_requiresAuthentication() async {
        #expect(await HistoryLockPolicy.unlock(using: StubUserAuthenticator(available: true, grants: true)))
        #expect(await !HistoryLockPolicy.unlock(using: StubUserAuthenticator(available: true, grants: false)))
    }

    @Test("with nothing able to authenticate, history stays locked instead of unlocking itself")
    func unlock_failsClosedWhenNothingCanAuthenticate() async {
        #expect(await !HistoryLockPolicy.unlock(using: StubUserAuthenticator(available: false, grants: true)))
    }

    @Test("under UI test the system authenticator is replaced, so no Touch ID prompt appears")
    func makeAuthenticator_underUITest_isAStub() async {
        let config = RuntimeConfiguration(mode: .uiTest, session: "s", seed: .basic, accessibility: .trusted)
        #expect(await !HistoryLockPolicy.unlock(using: UserAuthenticator.make(for: config, grants: false)))
        #expect(await HistoryLockPolicy.unlock(using: UserAuthenticator.make(for: config, grants: true)))
    }
}

/// The lock across a whole session, not just one decision: enable, unlock, work, idle out, unlock again.
@Suite("HistoryLockPolicy over time")
struct HistoryLockTimelineTests {
    @Test("locked at first, unlocked for the timeout after each unlock, locked again once idle")
    func whenSessionPlaysOut_thenLockFollowsTheTimeout() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func locked(at offset: TimeInterval, lastUnlock: Date?) -> Bool {
            HistoryLockPolicy.isLocked(
                enabled: true, timeoutMinutes: 5, lastUnlock: lastUnlock, now: start.addingTimeInterval(offset)
            )
        }

        #expect(locked(at: 0, lastUnlock: nil))
        #expect(!locked(at: 60, lastUnlock: start.addingTimeInterval(30)))
        #expect(!locked(at: 30 + 299, lastUnlock: start.addingTimeInterval(30)))
        #expect(locked(at: 30 + 300, lastUnlock: start.addingTimeInterval(30)))
        #expect(!locked(at: 30 + 301, lastUnlock: start.addingTimeInterval(30 + 301)))
    }
}

@Suite("Switching the lock back on")
struct LockSwitchedOnTests {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("an unlock from before the lock was switched on no longer counts")
    func whenUnlockPredatesSwitchOn_thenIgnored() {
        #expect(HistoryLockPolicy.effectiveLastUnlock(day, switchedOnAt: day.addingTimeInterval(60)) == nil)
    }

    @Test("an unlock after it counts, and so does any unlock when the lock was never switched on")
    func whenUnlockFollowsSwitchOn_thenKept() {
        #expect(HistoryLockPolicy.effectiveLastUnlock(day, switchedOnAt: day.addingTimeInterval(-60)) == day)
        #expect(HistoryLockPolicy.effectiveLastUnlock(day, switchedOnAt: nil) == day)
        #expect(HistoryLockPolicy.effectiveLastUnlock(nil, switchedOnAt: day) == nil)
    }

    @Test("switching the lock on records when")
    func whenSwitchedOn_thenTimeStored() {
        let defaults = ThrowawayDefaults.make()

        HistoryLockPolicy.lockWasSwitchedOn(at: day, defaults: defaults)

        #expect(defaults.object(forKey: HistoryLockPolicy.switchedOnKey) as? Date == day)
    }
}

@Suite("Starting the embedded Touch ID prompt again")
struct BiometricRetryTests {
    @Test("a prompt the system cancelled is started again, twice at most")
    func whenSystemCancelled_thenRetriedTwice() {
        let code = LAError.systemCancel.rawValue
        #expect(HistoryLockPolicy.shouldRetryBiometric(errorCode: code, attempt: 0))
        #expect(HistoryLockPolicy.shouldRetryBiometric(errorCode: code, attempt: 1))
        #expect(!HistoryLockPolicy.shouldRetryBiometric(errorCode: code, attempt: 2))
    }

    @Test("the app being unable to show UI yet is retried too")
    func whenNotInteractiveOrAppCancelled_thenRetried() {
        #expect(HistoryLockPolicy.shouldRetryBiometric(errorCode: LAError.notInteractive.rawValue, attempt: 0))
        #expect(HistoryLockPolicy.shouldRetryBiometric(errorCode: LAError.appCancel.rawValue, attempt: 0))
    }

    @Test("a wrong finger, the user's cancel and lockout are never retried by themselves")
    func whenUserOutcome_thenNotRetried() {
        for error in [
            LAError.authenticationFailed,
            .userCancel,
            .biometryLockout,
            .biometryNotAvailable,
            .userFallback
        ] {
            #expect(!HistoryLockPolicy.shouldRetryBiometric(errorCode: error.rawValue, attempt: 0))
        }
    }
}
