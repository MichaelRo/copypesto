// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

private final class CountingAuthenticator: UserAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var asked = 0
    let grants: Bool

    init(grants: Bool = true) {
        self.grants = grants
    }

    var timesAsked: Int {
        lock.withLock { asked }
    }

    func canAuthenticate() -> Bool {
        true
    }

    func authenticate(reason _: String) async -> Bool {
        lock.withLock { asked += 1 }
        return grants
    }
}

@Suite("Authentication stays valid for a while")
struct AuthenticationGraceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("nothing is valid until someone has authenticated")
    func whenNeverAuthenticated_thenNotActive() {
        #expect(!AuthenticationGrace().isActive(window: 300, now: now))
    }

    @Test("it is valid inside the window, ends after it, and a zero window means every time")
    func whenRecorded_thenValidOnlyInsideTheWindow() {
        let grace = AuthenticationGrace()
        grace.record(now: now)

        #expect(grace.isActive(window: 300, now: now.addingTimeInterval(299)))
        #expect(!grace.isActive(window: 300, now: now.addingTimeInterval(301)))
        #expect(!grace.isActive(window: 0, now: now))
    }

    @Test("clearing ends it at once")
    func whenCleared_thenNotActive() {
        let grace = AuthenticationGrace()
        grace.record(now: now)
        grace.clear()
        #expect(!grace.isActive(window: 300, now: now))
    }

    @Test("the second protected action inside the window is not asked again, and a fresh one always is")
    func whenSecondAction_thenOnlyAskedOnce() async {
        let grace = AuthenticationGrace()
        let authenticator = CountingAuthenticator()

        let first = await grace.verify(using: authenticator, reason: "a", window: 300, now: now)
        let second = await grace.verify(using: authenticator, reason: "b", window: 300, now: now.addingTimeInterval(60))
        let fresh = await grace.verify(
            using: authenticator, reason: "c", requireFresh: true, window: 300, now: now.addingTimeInterval(61)
        )
        let later = await grace.verify(
            using: authenticator,
            reason: "d",
            window: 300,
            now: now.addingTimeInterval(1000)
        )

        #expect(first && second && fresh && later)
        #expect(authenticator.timesAsked == 3, "asked for the first, the fresh one and the one after the window")
    }

    @Test("a refused authentication starts no window")
    func whenRefused_thenNothingRecorded() async {
        let grace = AuthenticationGrace()
        let refused = await grace.verify(
            using: CountingAuthenticator(grants: false),
            reason: "a",
            window: 300,
            now: now
        )
        #expect(!refused)
        #expect(!grace.isActive(window: 300, now: now))
    }

    @Test("the window is the person's choice, five minutes unless they change it")
    func window_comesFromThePreferences() {
        let defaults = ThrowawayDefaults.make()
        #expect(AuthenticationGrace.window(defaults: defaults) == 300)
        for minutes in AuthenticationGrace.choices {
            defaults.set(minutes, forKey: AuthenticationGrace.minutesKey)
            #expect(AuthenticationGrace.window(defaults: defaults) == TimeInterval(minutes * 60))
        }
        for unknown in [0, 7, 1440] {
            defaults.set(unknown, forKey: AuthenticationGrace.minutesKey)
            #expect(AuthenticationGrace.window(defaults: defaults) == 300, "\(unknown) falls back to five minutes")
        }
    }

    @Test("one setting, four choices: a minute, five, fifteen, an hour")
    func choices_areTheOneAuthenticationWindow() {
        #expect(AuthenticationGrace.choices == [1, 5, 15, 60])
    }
}

@Suite("AuthenticationWindowMigration: the lock timeout and the grace window become one setting")
struct AuthenticationWindowMigrationTests {
    private func migrate(
        lockOn: Bool, lockMinutes: Int? = nil, graceMinutes: Int? = nil
    )
    -> (minutes: Int?, defaults: UserDefaults) {
        let defaults = ThrowawayDefaults.make()
        defaults.set(lockOn, forKey: "biometricLockEnabled")
        if let lockMinutes { defaults.set(lockMinutes, forKey: "biometricLockTimeoutMinutes") }
        if let graceMinutes { defaults.set(graceMinutes, forKey: AuthenticationGrace.minutesKey) }
        AuthenticationWindowMigration.run(defaults: defaults)
        return (defaults.object(forKey: AuthenticationGrace.minutesKey) as? Int, defaults)
    }

    @Test("with the lock on, the person's lock timeout becomes the window, because the lock is what they felt")
    func whenLockIsOn_thenLockTimeoutWins() {
        #expect(migrate(lockOn: true, lockMinutes: 15, graceMinutes: 1).minutes == 15)
        #expect(migrate(lockOn: true, lockMinutes: 60, graceMinutes: 5).minutes == 60)
    }

    @Test("a lock timeout of a day, which the one setting does not offer, becomes an hour")
    func whenLockedForADay_thenAnHour() {
        #expect(migrate(lockOn: true, lockMinutes: 1440).minutes == 60)
    }

    @Test("with the lock on and no timeout chosen, the default five minutes stands")
    func whenLockOnAndUnset_thenDefault() {
        #expect(migrate(lockOn: true).minutes == 5)
    }

    @Test("with the lock off, the grace window stays, and 'every time' becomes one minute")
    func whenLockIsOff_thenGraceStays() {
        #expect(migrate(lockOn: false, lockMinutes: 60, graceMinutes: 15).minutes == 15)
        #expect(migrate(lockOn: false, graceMinutes: 0).minutes == 1)
        #expect(migrate(lockOn: false).minutes == nil, "nothing chosen stays nothing chosen")
    }

    @Test("it runs once: a later choice is not overwritten by an old lock timeout")
    func whenRunTwice_thenTheSecondDoesNothing() {
        let (_, defaults) = migrate(lockOn: true, lockMinutes: 15)
        defaults.set(5, forKey: AuthenticationGrace.minutesKey)

        AuthenticationWindowMigration.run(defaults: defaults)

        #expect(defaults.integer(forKey: AuthenticationGrace.minutesKey) == 5)
    }
}
