// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// One clip on the keyboard: Pesto's card (`QuickInsertCardFace`) with what only the keyboard adds, the feedback
/// after an insert or a copy and the copy mark on a picture.
struct KeyboardClipKey: View {
    enum Feedback: Equatable {
        case inserted
        case copiedImage
    }

    let entry: QuickInsertEntry
    let cardSize: CGSize
    let feedback: Feedback?
    var theme: WidgetSnapshot.Theme = .brand
    var appIcon: Data?

    @Environment(\.pestoAccent) private var accent
    @Environment(\.pestoAccentLabel) private var accentLabel
    @State private var loadedPicture: KeyboardThumbnails.Picture?

    var body: some View {
        let picture = KeyboardThumbnails.shared.cachedPicture(for: entry.id) ?? loadedPicture
        QuickInsertCardFace(
            entry: entry, size: cardSize, theme: theme, appIcon: appIcon,
            picture: picture?.image, backdrop: picture?.backdrop
        )
        .task(id: entry.id) {
            guard let data = entry.thumbnail else { return }
            if KeyboardThumbnails.shared.cachedPicture(for: entry.id) != nil { return }
            loadedPicture = await KeyboardThumbnails.shared.loadPicture(for: entry.id, data: data)
        }
        .overlay {
            if feedback != nil {
                QuickInsertCardFace.shape.strokeBorder(accent, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if entry.kind == .image, feedback == nil {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption2.weight(.semibold))
                    .padding(5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .center) {
            if let feedback {
                feedbackBadge(feedback)
            }
        }
        .contentShape(QuickInsertCardFace.shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(Text(Self.accessibilityValue(of: entry)))
        .accessibilityHint(entry.kind == .image ? Text("Copies this picture") : Text("Inserts this clip"))
        .accessibilityAddTraits(.isButton)
    }

    private func feedbackBadge(_ feedback: Feedback) -> some View {
        let text: LocalizedStringKey = switch feedback {
        case .inserted: "Inserted \u{2713}"
        case .copiedImage: "Copied, paste it"
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accentLabel)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accent, in: Capsule())
            .padding(6)
    }

    private var accessibilityTitle: String {
        if entry.kind == .image {
            return entry.customTitle ?? entry.recognizedText ?? String(localized: "Picture")
        }
        return entry.label()
    }

    private static func accessibilityValue(of entry: QuickInsertEntry) -> String {
        let kind = entry.expandsOnInsert ? String(localized: "Snippet") : entry.kind.presentation.label
        return entry.fromAnotherDevice ? kind + ", " + String(localized: "from another device") : kind
    }
}
