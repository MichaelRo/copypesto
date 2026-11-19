// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The first-run welcome (ADR 0057): shown once over the library, again only when Settings asks, and never in a test
/// or UI-test launch unless it is asked for.
extension MobileAppState {
    func presentWelcomeOnFirstLaunch(
        defaults: UserDefaults = AppDefaults.store, isLive: Bool = LaunchMode.current == .normal
    ) {
        guard isLive || defaults.value(for: Setting.uitestShowsWelcome) else { return }
        guard !showsWelcome, !isHistoryLocked, !defaults.value(for: Setting.welcomeShown) else { return }
        defaults.set(true, for: Setting.welcomeShown)
        showsWelcome = true
    }

    func showWelcomeAgain() {
        showsWelcome = true
    }

    /// Settings closes first and then asks for the welcome, since a screen cannot present over a sheet that is leaving.
    func requestWelcomeAgain() {
        welcomeAgainRequested = true
    }

    func takeWelcomeAgainRequest() -> Bool {
        defer { welcomeAgainRequested = false }
        return welcomeAgainRequested
    }

    func closeWelcome(startingSync: Bool = false) {
        syncSetUpRequested = startingSync
        showsWelcome = false
    }

    /// Nothing starts sync setup while the history is locked: the request is dropped, not kept for the unlock.
    func takeSyncSetUpRequest() -> Bool {
        defer { syncSetUpRequested = false }
        return syncSetUpRequested && !isHistoryLocked
    }

    /// Turning the lock on from the welcome asks for Face ID, Touch ID or the passcode first; a refusal leaves it off.
    func turnOnHistoryLock(defaults: UserDefaults = AppDefaults.store) async -> Bool {
        guard await HistoryLockPolicy.permitsSensitiveAction(
            using: historyLock.authenticator, reason: String(localized: "Turn on the history lock"),
            requireFresh: true, grace: historyLock.grace
        ) else { return false }
        defaults.set(true, for: Setting.biometricLockEnabled)
        historyLockSettingChanged()
        return true
    }
}
