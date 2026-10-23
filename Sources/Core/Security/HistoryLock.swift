// SPDX-License-Identifier: MIT
import Foundation
import LocalAuthentication

public protocol UserAuthenticating: Sendable {
    func canAuthenticate() -> Bool
    func authenticate(reason: String) async -> Bool
}

/// Whether this Mac can ask the person to prove who they are at all: Touch ID, Apple Watch or an account password. A
/// Mac with none of them cannot unlock, show a hidden clip or reveal a key, so those controls are not offered there.
public enum AuthenticationAvailability: Equatable, Sendable {
    case available
    case unavailable

    /// What to tell the person, and how to fix it. Nil when nothing is wrong.
    public var explanation: String? {
        self == .unavailable
            ? "This Mac has no login password or Touch ID to ask for. Set a login password in System Settings > "
            + "Users & Groups to use this."
            : nil
    }
}

public extension UserAuthenticating {
    var availability: AuthenticationAvailability {
        canAuthenticate() ? .available : .unavailable
    }
}

public enum HistoryLockPolicy {
    public static let defaultTimeoutMinutes = Setting.biometricLockTimeoutMinutes.defaultValue

    /// The lock is not offered where nothing could ever unlock it.
    public static func canSwitchOn(using authenticator: any UserAuthenticating) -> Bool {
        authenticator.availability == .available
    }

    /// Switching the lock off needs authentication, except where nothing can authenticate: there it protects no one,
    /// and refusing would trap a Mac whose password was removed after the lock was switched on.
    public static func permitsTurningLockOff(
        using authenticator: any UserAuthenticating,
        reason: String,
        grace: AuthenticationGrace = .shared
    )
    async -> Bool {
        guard authenticator.canAuthenticate() else { return true }
        return await grace.verify(using: authenticator, reason: reason, requireFresh: true)
    }

    /// Showing a recovery key or letting a password manager's copies be kept: authenticate first, and where nothing
    /// can authenticate the answer is no (the action is not offered there).
    public static func permitsSensitiveAction(
        using authenticator: any UserAuthenticating,
        reason: String,
        requireFresh: Bool = false,
        grace: AuthenticationGrace = .shared
    )
    async -> Bool {
        guard authenticator.canAuthenticate() else { return false }
        return await grace.verify(using: authenticator, reason: reason, requireFresh: requireFresh)
    }

    /// Whether history is locked right now. A timeout that is zero or negative (an unset preference reads as 0)
    /// is not "never lock": it falls back to the default, so the lock cannot silently switch itself off.
    public static func isLocked(enabled: Bool, timeoutMinutes: Int, lastUnlock: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastUnlock else { return true }
        let minutes = timeoutMinutes > 0 ? timeoutMinutes : defaultTimeoutMinutes
        return now.timeIntervalSince(lastUnlock) >= Double(minutes) * 60
    }

    /// The lock screen asks for Touch ID by itself as soon as it is shown, so unlocking is one step. It never asks
    /// while
    /// hidden, and a cancelled prompt is not repeated: the unlock button stays as the fallback.
    public static func shouldPromptAutomatically(isLocked: Bool, isVisible: Bool) -> Bool {
        isLocked && isVisible
    }

    public static let maxAutomaticBiometricRetries = 2
    public static let biometricStartDelay: Duration = .milliseconds(250)

    /// The embedded prompt is dismissed by the system when focus moves or the shelf is still appearing; those
    /// cancellations are not the user saying no, so the prompt is started again a couple of times before the
    /// "Try Again" button appears. A wrong finger, the user's own cancel and lockout are never retried.
    public static func shouldRetryBiometric(errorCode: Int, attempt: Int) -> Bool {
        guard attempt < maxAutomaticBiometricRetries else { return false }
        return [LAError.systemCancel, LAError.appCancel, LAError.notInteractive].map(\.rawValue).contains(errorCode)
    }

    /// Turning the lock off, exporting or importing history and restoring settings are things a person at an
    /// unattended Mac must not be able to do around the lock. With the lock off nothing is asked; with it on, only a
    /// successful authentication allows the action, and nothing able to authenticate means no.
    public static func permitsProtectedAction(
        lockEnabled: Bool,
        using authenticator: any UserAuthenticating,
        reason: String,
        requireFresh: Bool = false,
        grace: AuthenticationGrace = .shared
    )
    async -> Bool {
        guard lockEnabled else { return true }
        guard authenticator.canAuthenticate() else { return false }
        return await grace.verify(using: authenticator, reason: reason, requireFresh: requireFresh)
    }

    /// The last-item file holds plaintext outside the encrypted store, so it must not survive the lock being turned on.
    public static func lockWasSwitchedOn(at date: Date = .now, defaults: UserDefaults = AppDefaults.store) {
        LastItemStore.clear()
        defaults.set(date, forKey: switchedOnKey)
    }

    public static let switchedOnKey = "historyLockSwitchedOnAt"

    /// An unlock from before the lock was last switched on belongs to an earlier session: turning the lock off and
    /// on again must lock at once, not ride on the unlock that preceded it.
    public static func effectiveLastUnlock(_ lastUnlock: Date?, switchedOnAt: Date?) -> Date? {
        guard let lastUnlock else { return nil }
        guard let switchedOnAt else { return lastUnlock }
        return lastUnlock >= switchedOnAt ? lastUnlock : nil
    }

    /// True only if the user authenticated. When nothing can authenticate, history stays locked.
    public static func unlock(
        using authenticator: any UserAuthenticating,
        grace: AuthenticationGrace = .shared
    ) async
    -> Bool {
        guard authenticator.canAuthenticate() else { return false }
        guard await authenticator.authenticate(reason: "Unlock your clipboard history") else { return false }
        grace.record()
        return true
    }
}

/// Showing the real content of a clip that is hidden on the shelf (a secret, or a copy kept from a password manager)
/// outside the shelf, such as in Quick Look: the mask is only worth having if the way round it asks first.
public enum HiddenClipReveal {
    /// The start of a hidden clip's text, for showing in place once the person has been authenticated. Nil when the
    /// payload is missing or is not text.
    public static func readableText(from payload: Data?, limit: Int = 500) -> String? {
        guard let payload, let text = String(data: payload, encoding: .utf8) else { return nil }
        return String(text.prefix(limit))
    }

    public static func permitted(
        isHidden: Bool,
        using authenticator: any UserAuthenticating,
        reason: String,
        grace: AuthenticationGrace = .shared
    ) async
    -> Bool {
        guard isHidden else { return true }
        guard authenticator.canAuthenticate() else { return false }
        return await grace.verify(using: authenticator, reason: reason)
    }
}

/// Touch ID, Apple Watch or the account password, whichever the Mac offers.
public struct SystemUserAuthenticator: UserAuthenticating {
    public init() {}

    public func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public func authenticate(reason: String) async -> Bool {
        await (try? LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

public struct StubUserAuthenticator: UserAuthenticating {
    public let available: Bool
    public let grants: Bool

    public init(available: Bool, grants: Bool) {
        self.available = available
        self.grants = grants
    }

    public func canAuthenticate() -> Bool {
        available
    }

    public func authenticate(reason _: String) async -> Bool {
        grants
    }
}

public enum UserAuthenticator {
    public static var current: any UserAuthenticating {
        make(
            for: RuntimeConfiguration.current,
            grants: AppDefaults.store.value(for: Setting.uitestAuthenticationGranted),
            available: !AppDefaults.store.value(for: Setting.uitestAuthenticationUnavailable)
        )
    }

    static func make(
        for configuration: RuntimeConfiguration,
        grants: Bool,
        available: Bool = true
    )
    -> any UserAuthenticating {
        configuration.mode == .normal
            ? SystemUserAuthenticator()
            : StubUserAuthenticator(available: available, grants: grants)
    }
}
