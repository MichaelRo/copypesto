// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore

/// Which hidden clips the person has shown (ADR 0003). Show asks for Face ID, Touch ID or the passcode unless the
/// shared `AuthenticationGrace` window is open; everything shown hides again when Pesto leaves the foreground.
@MainActor
@Observable
final class SecretReveal {
    private(set) var shown: Set<UUID> = []
    @ObservationIgnored private let authenticator: any UserAuthenticating
    @ObservationIgnored private let grace: AuthenticationGrace

    init(authenticator: any UserAuthenticating = UserAuthenticator.current, grace: AuthenticationGrace = .shared) {
        self.authenticator = authenticator
        self.grace = grace
    }

    var canAuthenticate: Bool {
        authenticator.canAuthenticate()
    }

    func isShown(_ id: UUID) -> Bool {
        shown.contains(id)
    }

    @discardableResult
    func show(_ id: UUID, reason: String) async -> Bool {
        let permitted = await HiddenClipReveal.permitted(
            isHidden: true, using: authenticator, reason: reason, grace: grace
        )
        if permitted { shown.insert(id) }
        return permitted
    }

    func hide(_ id: UUID) {
        shown.remove(id)
    }

    func hideAll() {
        if !shown.isEmpty { shown = [] }
    }

    /// As the Mac's card decides it: a picture still being judged is drawn (only text waits for its verdict).
    func concealment(for item: ClipboardItem, nsfwMode: NSFWMode = .current()) -> CardConcealment {
        CardConcealment(
            screenShareBlur: false,
            nsfwBlurred: item.isNSFW && nsfwMode != .show,
            maskedSecret: item.sensitivityRaw != nil,
            secretShown: isShown(item.id),
            pendingAnalysis: item.analysisPending && item.type != .image
        )
    }
}
