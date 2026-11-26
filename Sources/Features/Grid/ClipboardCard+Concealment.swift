// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

extension ClipboardCard {
    var concealment: CardConcealment {
        CardConcealment(
            screenShareBlur: isCoveredForPrivacy,
            nsfwBlurred: isBlurredAsSensitive,
            maskedSecret: item.sensitivity != nil,
            secretShown: revealedSecret != nil,
            pendingAnalysis: waitsForVerdict
        )
    }

    /// Covered until the verdict: a large text always, a picture while the content filter screens pictures (ADR 0079).
    var waitsForVerdict: Bool {
        CardConcealment.waitsForVerdict(type: item.type, analysisPending: item.analysisPending, nsfwMode: nsfwMode)
    }

    /// A picture waiting for its verdict draws only its placeholder: its pixels are neither decoded for the card nor
    /// shown.
    var pictureWaitsForVerdict: Bool {
        item.type == .image && waitsForVerdict
    }

    /// Covered for a screen share or by hand, until the person shows this card with its Show. Showing it is not
    /// permanent: the cover coming back, or the shelf closing, covers it again.
    var isCoveredForPrivacy: Bool {
        isPrivacyBlurred && !(isNSFWRevealed || revealedFromOutside)
    }

    /// Anything that keeps the card's text from being drawn: a content-filter blur, a secret's mask, or the cover for a
    /// screen share.
    var hidesItsContent: Bool {
        isBlurredAsSensitive || isCoveredForPrivacy || item.sensitivity != nil
    }

    /// Asked when the menu opens: a covered card offers nothing, a masked secret only while it is shown (ADR 0050).
    var offersTextEdit: Bool {
        TextEditPolicy.isOffered(
            type: item.type, analysisPending: item.analysisPending, hasBlob: item.blob != nil,
            byteSize: item.byteSize, concealment: concealment
        )
    }

    var isBlurredAsSensitive: Bool {
        item.isNSFW && nsfwMode.blursCards && !(isNSFWRevealed || revealedFromOutside)
    }
}
