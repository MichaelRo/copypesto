// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What the hover card shows, for the VoiceOver "More Content" rotor: the card is a window that keyboard focus never
/// enters, so the focused clip carries it. An empty entry adds nothing.
struct VoiceOverDetails: Equatable {
    var details = ""
    var text = ""
    var title = ""
    var note = ""
    var files = ""
    var inPicture = ""

    static func make(
        for item: ClipboardItem,
        collectionName: String?,
        isBlurredAsSensitive: Bool,
        isCoveredForPrivacy: Bool
    )
    -> VoiceOverDetails {
        var content = VoiceOverDetails()
        let facts = DetailFactsText.facts(
            for: item,
            collectionName: collectionName,
            shownText: item.gridPreview,
            wasCut: false
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
            content.text = String(preview.prefix(CardPreviewText.previewLength)) +
                (item.textLength > CardPreviewText.previewLength ? " … Quick Look shows the rest." : "")
        case .url:
            content.title = [item.ogTitle ?? item.customTitle, item.ogSiteName].compactMap(\.self)
                .joined(separator: ", ")
            content.text = String(item.gridPreview.prefix(CardPreviewText.previewLength))
        case .file:
            content.files = FileClip.urls(from: item.displayPreviewText).prefix(6).map(\.lastPathComponent)
                .joined(separator: ", ")
        case .image:
            content.inPicture = String(
                item.displayPreviewText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)
            )
        case .color:
            break
        }
        return content
    }
}

extension View {
    func voiceOverContent(_ content: VoiceOverDetails) -> some View {
        accessibilityCustomContent(AccessibilityCustomContentKey("Details"), content.details, importance: .high)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Text"), content.text)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Title"), content.title)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Note"), content.note)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Files"), content.files)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Text in the picture"), content.inPicture)
    }
}
