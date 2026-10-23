// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// When someone has just proved who they are, the next protected action does not ask again for a while, the way
/// `sudo` and System Settings behave. One window serves the History Lock, showing a hidden clip, backups and the other
/// protected actions; actions that cannot be undone (clearing everything, showing the recovery key) always ask.
/// It lives in memory only, so quitting ends it, and the history locking or the screen locking clears it.
public final class AuthenticationGrace: Sendable {
    public static let shared = AuthenticationGrace()
    public static let minutesKey = Setting.authenticationGraceMinutes.name
    public static let choices = [1, 5, 15, 60]
    public static let defaultMinutes = Setting.authenticationGraceMinutes.defaultValue

    private let lastSuccess = Mutex<Date?>(nil)

    public init() {}

    /// The window in seconds from the person's setting. It also decides when the History Lock engages again.
    public static func window(defaults: UserDefaults = AppDefaults.store) -> TimeInterval {
        TimeInterval(minutes(defaults: defaults) * 60)
    }

    public static func minutes(defaults: UserDefaults = AppDefaults.store) -> Int {
        guard defaults.object(forKey: minutesKey) != nil else { return defaultMinutes }
        let minutes = defaults.integer(forKey: minutesKey)
        return choices.contains(minutes) ? minutes : defaultMinutes
    }

    public func isActive(window: TimeInterval = AuthenticationGrace.window(), now: Date = .now) -> Bool {
        guard window > 0, let last = lastSuccess.withLock({ $0 }) else { return false }
        return now.timeIntervalSince(last) < window
    }

    public func record(now: Date = .now) {
        lastSuccess.withLock { $0 = now }
    }

    public func clear() {
        lastSuccess.withLock { $0 = nil }
    }

    /// True if the person authenticated just now or earlier inside the window. A success starts a new window.
    public func verify(
        using authenticator: any UserAuthenticating,
        reason: String,
        requireFresh: Bool = false,
        window: TimeInterval = AuthenticationGrace.window(),
        now: Date = .now
    ) async
    -> Bool {
        if !requireFresh, isActive(window: window, now: now) { return true }
        guard await authenticator.authenticate(reason: reason) else { return false }
        record(now: now)
        return true
    }
}

/// The History Lock's timeout and the grace window after a Touch ID were two settings that the person read as one
/// (ADR 0003). This moves what they chose into the one that remains, once. With the lock on, its timeout is what they
/// felt, so it wins; with it off, the grace window stays. A choice the single setting no longer offers ("Every time",
/// a day) becomes the nearest one it does.
public enum AuthenticationWindowMigration {
    public static let doneKey = Setting.authenticationWindowMigrated.name

    public static func run(defaults: UserDefaults = AppDefaults.store) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        if defaults.bool(forKey: Setting.biometricLockEnabled.name) {
            let lockMinutes = defaults.object(forKey: Setting.biometricLockTimeoutMinutes.name) as? Int
            let chosen = nearestChoice(lockMinutes ?? AuthenticationGrace.defaultMinutes)
            defaults.set(chosen, forKey: AuthenticationGrace.minutesKey)
        } else if let grace = defaults.object(forKey: AuthenticationGrace.minutesKey) as? Int {
            defaults.set(nearestChoice(grace), forKey: AuthenticationGrace.minutesKey)
        }
    }

    private static func nearestChoice(_ minutes: Int) -> Int {
        if AuthenticationGrace.choices.contains(minutes) { return minutes }
        if minutes <= 0 { return AuthenticationGrace.choices[0] }
        return AuthenticationGrace.choices.last { $0 <= minutes } ?? AuthenticationGrace.defaultMinutes
    }
}
