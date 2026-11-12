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
            pendingAnalysis: item.analysisPending && item.type != .image
        )
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

    var isBlurredAsSensitive: Bool {
        item.isNSFW && nsfwMode.blursCards && !(isNSFWRevealed || revealedFromOutside)
    }
}
