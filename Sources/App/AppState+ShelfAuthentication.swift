// SPDX-License-Identifier: MIT
import LocalAuthentication
import PestoCore

/// A request for Touch ID that the shelf answers itself, so the system dialog never takes focus from the shelf and
/// closes it (the same reason the History Lock asks inside the shelf).
struct ShelfAuthenticationRequest: Equatable {
    let id = UUID()
    let reason: String
}

extension AppState {
    static var embeddedBiometricsAvailable: Bool {
        LaunchMode.current.usesSystemIntegrations
            && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// True if the person authenticated now or recently enough (`AuthenticationGrace`). With Touch ID available and the
    /// shelf open the prompt is drawn inside the shelf; otherwise the system authenticator is used, which can pull
    /// focus from the shelf (the password fallback, and Macs without Touch ID).
    func authenticateInShelf(
        reason: String,
        authenticator: any UserAuthenticating = UserAuthenticator.current,
        embeddedAvailable: Bool = AppState.embeddedBiometricsAvailable,
        grace: AuthenticationGrace = .shared
    ) async
    -> Bool {
        if grace.isActive() { return true }
        guard authenticator.canAuthenticate() else { return false }
        guard embeddedAvailable, isOverlayVisible else {
            let delay: Duration = LaunchMode.current.usesSystemIntegrations ? .milliseconds(200) : .zero
            return await withSystemAuthenticationDialog(settleDelay: delay) {
                await grace.verify(using: authenticator, reason: reason)
            }
        }
        guard shelfAuthentication == nil else { return false }
        return await withCheckedContinuation { continuation in
            shelfAuthenticationContinuation = continuation
            shelfAuthentication = ShelfAuthenticationRequest(reason: reason)
        }
    }

    /// The shelf stays open while Touch ID is drawn in it or the system's password dialog is up: that dialog takes
    /// focus
    /// and takes the clicks made in it, which would otherwise read as a click outside the shelf and close it.
    var keepsShelfOpenForAuthentication: Bool {
        shelfAuthentication != nil || systemAuthenticationDialogs > 0
    }

    /// Runs a system authentication (the password dialog) with the shelf held open, then gives the shelf its keys back.
    func withSystemAuthenticationDialog<T>(
        settleDelay: Duration = .zero,
        _ body: () async -> T
    ) async
    -> T {
        systemAuthenticationDialogs += 1
        defer {
            systemAuthenticationDialogs -= 1
            onRestoreKeyFocus?()
        }
        let result = await body()
        if settleDelay > .zero {
            try? await Task.sleep(for: settleDelay)
        } else {
            await Task.yield()
        }
        return result
    }

    func finishShelfAuthentication(success: Bool, grace: AuthenticationGrace = .shared) {
        if success { grace.record() }
        guard let continuation = shelfAuthenticationContinuation else { return }
        shelfAuthenticationContinuation = nil
        shelfAuthentication = nil
        continuation.resume(returning: success)
    }
}
