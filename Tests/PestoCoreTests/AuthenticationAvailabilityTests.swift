// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("What this Mac can authenticate")
struct AuthenticationAvailabilityTests {
    @Test("an authenticator reports whether anything can authenticate")
    func availability_followsTheAuthenticator() {
        #expect(StubUserAuthenticator(available: true, grants: false).availability == .available)
        #expect(StubUserAuthenticator(available: false, grants: false).availability == .unavailable)
    }

    @Test("a Mac with nothing to authenticate with is told how to fix it")
    func unavailable_hasAWayToFixIt() {
        #expect(AuthenticationAvailability.unavailable.explanation?.contains("login password") == true)
        #expect(AuthenticationAvailability.available.explanation == nil)
    }

    @Test("the lock cannot be switched on where nothing could ever unlock it")
    func lockCanBeSwitchedOn_onlyWhenAvailable() {
        #expect(HistoryLockPolicy.canSwitchOn(using: StubUserAuthenticator(available: true, grants: false)))
        #expect(!HistoryLockPolicy.canSwitchOn(using: StubUserAuthenticator(available: false, grants: false)))
    }

    @Test("turning the lock off needs authentication, unless nothing can authenticate, so nobody is locked in")
    func turningTheLockOff_neverTrapsAnyone() async {
        let yes = StubUserAuthenticator(available: true, grants: true)
        let no = StubUserAuthenticator(available: true, grants: false)
        let cannot = StubUserAuthenticator(available: false, grants: false)

        #expect(await HistoryLockPolicy.permitsTurningLockOff(using: yes, reason: "x", grace: AuthenticationGrace()))
        #expect(await !HistoryLockPolicy.permitsTurningLockOff(using: no, reason: "x", grace: AuthenticationGrace()))
        #expect(await HistoryLockPolicy.permitsTurningLockOff(using: cannot, reason: "x", grace: AuthenticationGrace()))
    }

    @Test("showing a recovery key or allowing an app asks first, and fails closed when nothing can ask")
    func sensitiveAction_failsClosed() async {
        let yes = StubUserAuthenticator(available: true, grants: true)
        let no = StubUserAuthenticator(available: true, grants: false)
        let cannot = StubUserAuthenticator(available: false, grants: true)

        #expect(await HistoryLockPolicy.permitsSensitiveAction(using: yes, reason: "x", grace: AuthenticationGrace()))
        #expect(await !HistoryLockPolicy.permitsSensitiveAction(using: no, reason: "x", grace: AuthenticationGrace()))
        #expect(await !HistoryLockPolicy.permitsSensitiveAction(
            using: cannot,
            reason: "x",
            grace: AuthenticationGrace()
        ))
    }
}
