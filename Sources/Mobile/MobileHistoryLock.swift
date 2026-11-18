// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore

/// The History Lock on iPhone and iPad (ADR 0054), decided by the Mac's `HistoryLockPolicy` with the one
/// `AuthenticationGrace` window as its timeout: locked at launch, and again once Pesto has been out of the foreground
/// for that long. An unlock starts a new grace window, as on the Mac.
@MainActor
@Observable
final class MobileHistoryLock {
    private(set) var isLocked: Bool
    @ObservationIgnored private var leftForegroundAt: Date?
    @ObservationIgnored let authenticator: any UserAuthenticating
    @ObservationIgnored let grace: AuthenticationGrace
    @ObservationIgnored private let isEnabledNow: @MainActor () -> Bool
    @ObservationIgnored private let showsClipsOutsideNow: @MainActor () -> Bool
    @ObservationIgnored private let timeoutMinutes: @MainActor () -> Int

    init(
        authenticator: any UserAuthenticating = UserAuthenticator.current,
        grace: AuthenticationGrace = .shared,
        isEnabled: @escaping @MainActor () -> Bool = { AppDefaults.store.value(for: Setting.biometricLockEnabled) },
        timeoutMinutes: @escaping @MainActor () -> Int = { AuthenticationGrace.minutes() },
        showsClipsOutside: @escaping @MainActor () -> Bool = {
            AppDefaults.store.value(for: Setting.showsClipsOutsideWhileLocked)
        }
    ) {
        showsClipsOutsideNow = showsClipsOutside
        self.authenticator = authenticator
        self.grace = grace
        isEnabledNow = isEnabled
        self.timeoutMinutes = timeoutMinutes
        isLocked = isEnabled()
    }

    var isEnabled: Bool {
        isEnabledNow()
    }

    var holdsOutsideSurfaces: Bool {
        isEnabled && !showsClipsOutsideNow()
    }

    var canAuthenticate: Bool {
        authenticator.canAuthenticate()
    }

    func didLeaveForeground(at date: Date) {
        if !isLocked { leftForegroundAt = date }
    }

    /// Locks when Pesto has been away for the timeout. True only when this call locked it.
    @discardableResult
    func lockIfAwayTooLong(at date: Date) -> Bool {
        guard !isLocked, let leftForegroundAt else { return false }
        guard HistoryLockPolicy.isLocked(
            enabled: isEnabled, timeoutMinutes: timeoutMinutes(), lastUnlock: leftForegroundAt, now: date
        ) else { return false }
        lock()
        return true
    }

    func didBecomeActive() {
        leftForegroundAt = nil
    }

    func lock() {
        guard isEnabled else { return }
        isLocked = true
        leftForegroundAt = nil
        grace.clear()
    }

    /// True only when the person authenticated; with nothing able to authenticate the history stays locked.
    @discardableResult
    func unlock() async -> Bool {
        guard isLocked else { return true }
        guard await HistoryLockPolicy.unlock(using: authenticator, grace: grace) else { return false }
        isLocked = false
        return true
    }

    /// The setting was turned off (in Settings, or from the lock screen where nothing can authenticate).
    func lockWasTurnedOff() {
        isLocked = false
        leftForegroundAt = nil
    }
}
