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
    /// The Mac's screen-share cover (ADR 0003, ADR 0054): `ContentCover` over a recording, mirroring or AirPlay that
    /// iOS reports for the scene, with the Mac's setting; Hide Clip Contents covers by hand and is not saved.
    var isScreenCaptured = false {
        didSet { forgetShowsUnlessCovered() }
    }

    var coversWhileCaptured: Bool {
        didSet { forgetShowsUnlessCovered() }
    }

    var isHiddenByHand = false {
        didSet { forgetShowsUnlessCovered() }
    }

    private(set) var shownUnderCover: Set<UUID> = []
    private(set) var shownNSFW: Set<UUID> = []
    @ObservationIgnored private let authenticator: any UserAuthenticating
    @ObservationIgnored private let grace: AuthenticationGrace

    init(
        authenticator: any UserAuthenticating = UserAuthenticator.current, grace: AuthenticationGrace = .shared,
        coversWhileCaptured: Bool = AppDefaults.store.value(for: Setting.screenSharingPrivacy)
    ) {
        self.authenticator = authenticator
        self.grace = grace
        self.coversWhileCaptured = coversWhileCaptured
    }

    var isContentCovered: Bool {
        ContentCover.isCovered(manual: isHiddenByHand, settingOn: coversWhileCaptured, shareDetected: isScreenCaptured)
    }

    /// As the Mac's Show on a covered card: no authentication, until the cover lifts and comes back.
    func isCoveredForPrivacy(_ id: UUID) -> Bool {
        isContentCovered && !shownUnderCover.contains(id)
    }

    func showUnderCover(_ id: UUID) {
        if isContentCovered { shownUnderCover.insert(id) }
    }

    /// Told when the content cover goes up, so what was opened in a sheet from a hidden clip closes with it.
    @ObservationIgnored var coverWasRaised: (@MainActor () -> Void)?

    private func forgetShowsUnlessCovered() {
        if isContentCovered { coverWasRaised?() }
        if !isContentCovered, !shownUnderCover.isEmpty { shownUnderCover = [] }
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

    /// The same question Show asks, for an action that reads a hidden clip without showing it (Decode JWT).
    func authenticate(reason: String) async -> Bool {
        await HiddenClipReveal.permitted(isHidden: true, using: authenticator, reason: reason, grace: grace)
    }

    func isNSFWShown(_ id: UUID) -> Bool {
        shownNSFW.contains(id)
    }

    func showNSFW(_ id: UUID) {
        shownNSFW.insert(id)
    }

    func hideNSFW(_ id: UUID) {
        shownNSFW.remove(id)
    }

    func hide(_ id: UUID) {
        shown.remove(id)
    }

    func hideAll() {
        if !shown.isEmpty { shown = [] }
        if !shownUnderCover.isEmpty { shownUnderCover = [] }
        if !shownNSFW.isEmpty { shownNSFW = [] }
    }

    /// A picture still being judged waits behind its placeholder while the content filter is on, so an explicit
    /// picture or GIF never flashes before screening finishes (ADR 0079).
    func concealment(for item: ClipboardItem, nsfwMode: NSFWMode = .current()) -> CardConcealment {
        CardConcealment(
            screenShareBlur: isCoveredForPrivacy(item.id),
            nsfwBlurred: item.isNSFW && nsfwMode != .show && !isNSFWShown(item.id),
            maskedSecret: item.sensitivityRaw != nil,
            secretShown: isShown(item.id),
            pendingAnalysis: CardConcealment.waitsForVerdict(
                type: item.type, analysisPending: item.analysisPending, nsfwMode: nsfwMode
            )
        )
    }
}
