// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

extension ClipboardCard {
    /// The hover card's content for VoiceOver, which never sees the card. Nothing of a hidden clip but its facts.
    var voiceOverContent: VoiceOverDetails {
        VoiceOverDetails.make(
            for: item,
            collectionName: availableCollections.first { $0.id == item.collectionID }?.name,
            isBlurredAsSensitive: isBlurredAsSensitive,
            isCoveredForPrivacy: isCoveredForPrivacy
        )
    }

    /// Esc, a drag, a context menu or a timeout: the card is gone and does not come back until the pointer leaves.
    func closeDetailForGood() {
        hoverTask?.cancel()
        graceTask?.cancel()
        showDetailPopover = false
        detailSpent = true
    }

    func pointerInsideDetail(_ inside: Bool) {
        pointerInDetail = inside
        if inside {
            graceTask?.cancel()
            detailHeld = true
        } else if !isHovered {
            startDetailGrace()
        }
    }

    func startDetailGrace() {
        graceTask?.cancel()
        detailHeld = true
        graceTask = Task {
            try? await Task.sleep(for: DetailPopoverPolicy.grace)
            guard !Task.isCancelled, !pointerInDetail else { return }
            detailHeld = false
        }
    }

    /// The pointer is on the card or crossing to it: nothing times it out.
    private var isHeldOpen: Bool {
        detailHeld || pointerInDetail
    }

    func restartDetailPopoverTimer() {
        hoverTask?.cancel()
        guard DetailPopoverPolicy.wantsDetail(
            hovered: DetailPopoverPolicy.hoverCounts(hovered: isHovered, pointerMoved: hoverArmed),
            keyboardRevealed: revealsDetail, held: detailHeld,
            suppressed: detailSuppressed || isScrolling || !concealment.allowsHoverDetail, spent: detailSpent
        ) else {
            showDetailPopover = false
            return
        }
        hoverTask = Task {
            try? await Task.sleep(for: DetailPopoverPolicy.dwell)
            guard !Task.isCancelled else { return }
            // Asked here, once the pointer has rested, never while the card draws.
            detailCopiesText = item.type == .image && actions.recognizedTextOffered?(item) == true
            showDetailPopover = true
            guard let delay = DetailPopoverPolicy.autoCloseDelay(hovered: isHovered || isHeldOpen) else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            closeDetailForGood()
            actions.detailDismissed?()
        }
    }

    /// Copy Recognized Text as a VoiceOver action: on a picture that read some text; the action asks again when run.
    var recognizedTextAction: (() -> Void)? {
        guard item.type == .image, let copy = actions.copyRecognizedText,
              RecognizedText.hasText(item) else { return nil }
        return { _ = copy(item) }
    }

    var detailCard: some View {
        CardDetailPopover(
            item: item,
            collectionName: availableCollections.first { $0.id == item.collectionID }?.name,
            isRevealed: revealedSecret != nil,
            revealedText: revealedSecret,
            pictureImage: shownThumbnail?.image,
            pictureIsAnimated: shownThumbnail?.isAnimated ?? false,
            linkImage: urlOGImage,
            linkImageIsAnimated: urlOGImageIsAnimated,
            onScrollsChange: { detailScrolls = $0 },
            onCopyRecognizedText: detailCopiesText ? { actions.copyRecognizedText?(item) ?? false } : nil
        )
    }
}
