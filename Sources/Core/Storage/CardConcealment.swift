// SPDX-License-Identifier: MIT

/// Whether a card is covered (for screen sharing, or because it is sensitive and has not been shown), and so which of
/// its other ways of showing the clip must be switched off: the hover popover, Quick Look, an AI action's answer and a
/// drag, each of which shows or hands out what the cover hides.
public struct CardConcealment: Equatable, Sendable {
    public let isConcealed: Bool

    public init(screenShareBlur: Bool, sensitiveBlur: Bool) {
        isConcealed = screenShareBlur || sensitiveBlur
    }

    /// `nsfwBlurred` is a picture or clip blurred by the content filter; `maskedSecret` is a clip whose preview is a
    /// mask (a card number, a key), which stays covered until `secretShown` says its Show is running.
    /// `pendingAnalysis` is a clip saved before it was read and screened (`ClipboardItem.analysisPending`): it is
    /// covered
    /// until the verdict, because what it holds might be what the verdict hides.
    public init(
        screenShareBlur: Bool, nsfwBlurred: Bool, maskedSecret: Bool, secretShown: Bool, pendingAnalysis: Bool = false
    ) {
        self.init(
            screenShareBlur: screenShareBlur,
            sensitiveBlur: pendingAnalysis || nsfwBlurred || (maskedSecret && !secretShown)
        )
    }

    public var allowsHoverDetail: Bool {
        !isConcealed
    }

    public var allowsQuickLook: Bool {
        !isConcealed
    }

    public var allowsAIActions: Bool {
        !isConcealed
    }

    public var allowsDrag: Bool {
        !isConcealed
    }
}
