// SPDX-License-Identifier: MIT

/// Whether a card is covered (for screen sharing, or because it is sensitive and has not been shown), and so which of
/// its other ways of showing the clip must be switched off: the hover popover, Quick Look, an AI action's answer and a
/// drag, each of which shows or hands out what the cover hides.
public struct CardConcealment: Equatable, Sendable {
    public let isConcealed: Bool
    public let isNSFWBlurred: Bool
    /// Decode JWT reads a hidden token after the same authentication as Show (ADR 0020), so it is the one way in a
    /// masked cover allows; a screen share, Hide Clip Contents or a content filter cover does not.
    public let allowsDecode: Bool

    public init(screenShareBlur: Bool, sensitiveBlur: Bool) {
        isConcealed = screenShareBlur || sensitiveBlur
        isNSFWBlurred = sensitiveBlur
        allowsDecode = false
    }

    /// `nsfwBlurred` is a picture or clip blurred by the content filter; `maskedSecret` is a clip whose preview is a
    /// mask (a card number, a key), which stays covered until `secretShown` says its Show is running.
    /// `pendingAnalysis` is a clip saved before it was read and screened (`ClipboardItem.analysisPending`): it is
    /// covered
    /// until the verdict, because what it holds might be what the verdict hides.
    public init(
        screenShareBlur: Bool, nsfwBlurred: Bool, maskedSecret: Bool, secretShown: Bool, pendingAnalysis: Bool = false
    ) {
        isConcealed = screenShareBlur || pendingAnalysis || nsfwBlurred || (maskedSecret && !secretShown)
        isNSFWBlurred = nsfwBlurred
        allowsDecode = !screenShareBlur && !nsfwBlurred && !pendingAnalysis
    }

    /// A clip saved before it was judged stays covered until its verdict (ADR 0079). A picture waits only while the
    /// content filter screens pictures: with it off, nothing in the verdict could hide the picture, so it shows at once
    /// rather than after its text is read.
    public static func waitsForVerdict(type: ClipboardType, analysisPending: Bool, nsfwMode: NSFWMode) -> Bool {
        analysisPending && (type != .image || nsfwMode.detectsContent)
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

    public var allowsFootGlow: Bool {
        !isConcealed
    }
}
