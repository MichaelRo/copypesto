// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

extension ClipboardCard {
    /// The hover card's content for VoiceOver, which never sees the card. Nothing of a hidden clip but its facts.
    var voiceOverContent: VoiceOverDetails {
        var content = VoiceOverDetails()
        let facts = DetailFactsText.facts(
            for: item, collectionName: availableCollections.first { $0.id == item.collectionID }?.name,
            shownText: item.gridPreview, wasCut: false
        )
        let partialCode = item.type == .code && item.textLength > item.gridPreview.count
        content.details = DetailFactsText.line(facts.filter { fact in
            if partialCode, case .lines = fact { return false }
            return true
        })
        guard item.sensitivity == nil, !isBlurredAsSensitive, !isCoveredForPrivacy else { return content }
        content.note = item.userNote ?? ""
        switch item.type {
        case .text, .code:
            let preview = item.gridPreview
            content
                .text = String(preview.prefix(CardPreviewText.previewLength)) +
                (item.textLength > CardPreviewText.previewLength ? " … Quick Look shows the rest." : "")
        case .url:
            content.title = [item.ogTitle ?? item.customTitle, item.ogSiteName].compactMap(\.self)
                .joined(separator: ", ")
            content.text = String(item.gridPreview.prefix(CardPreviewText.previewLength))
        case .file:
            content.files = FileClip.urls(from: item.displayPreviewText).prefix(6).map(\.lastPathComponent)
                .joined(separator: ", ")
        case .image:
            content
                .inPicture = String(item.displayPreviewText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        case .color:
            break
        }
        return content
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
            showDetailPopover = true
            guard let delay = DetailPopoverPolicy.autoCloseDelay(hovered: isHovered || isHeldOpen) else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            closeDetailForGood()
            actions.detailDismissed?()
        }
    }

    var detailCard: some View {
        CardDetailPopover(
            item: item,
            collectionName: availableCollections.first { $0.id == item.collectionID }?.name,
            isRevealed: revealedSecret != nil,
            revealedText: revealedSecret,
            onScrollsChange: { detailScrolls = $0 }
        )
    }
}
