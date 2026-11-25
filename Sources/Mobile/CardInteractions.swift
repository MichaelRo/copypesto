// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A card drags out only when nothing covers it (`CardConcealment`); the content is opened when the drag starts, not
/// while the card draws.
struct CardDragSource: ViewModifier {
    let card: ClipCard

    func body(content: Content) -> some View {
        if card.concealment.allowsDrag {
            content.onDrag {
                guard let clip = ClipContent.of(card.item) else { return NSItemProvider() }
                return ClipDrag.provider(for: clip, clipID: card.item.id)
            }
        } else {
            content
        }
    }
}

/// One VoiceOver element per card: what it is, what it says (only the mask when covered), where it came from, its age
/// and its pin. Activating it copies, as a tap does.
struct CardAccessibility: ViewModifier {
    let card: ClipCard

    func body(content: Content) -> some View {
        let item = card.item
        let concealment = card.concealment
        let selecting = card.library.isSelecting
        let summary = ClipSummary.make(
            item,
            concealment: concealment,
            coveredForPrivacy: card.isCoveredForPrivacy,
            peerDeviceNames: card.appState.peerDeviceNames
        )
        let age = CardAge.spoken(interval: CardAge.interval(for: item, inCollection: false))
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CardSpeech.label(
                kind: item.type.presentation.label, summary: summary.title, source: summary.source, age: age,
                isPinned: item.isPinned
            ))
            .accessibilityHint(
                Text(selecting ? "Selects or deselects the clip." : "Copies the clip.")
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selecting && card.isSelected ? .isSelected : [])
            .accessibilityAction {
                if selecting {
                    card.library.toggleSelection(item.id)
                } else {
                    card.copy()
                }
            }
            .accessibilityAction(named: Text("Edit Details")) { card.library.open(item.id) }
            .accessibilityAction(named: Text(item.isPinned ? "Unpin" : "Pin")) { card.togglePin() }
            .modifier(OptionalAction(name: "Share", isOffered: !concealment.isConcealed) { card.share() })
            .modifier(OptionalAction(
                name: "Show",
                isOffered: card.isCoveredForPrivacy
                    || concealment.isNSFWBlurred
                    || item.sensitivityRaw != nil && concealment.isConcealed
            ) { card.show() })
            .modifier(OptionalAction(
                name: "Hide",
                isOffered: (item.sensitivityRaw != nil && card.appState.secretReveal.isShown(item.id))
                    || (item.isNSFW && card.appState.secretReveal.isNSFWShown(item.id))
            ) { card.hide() })
            .accessibilityAction(named: Text("Delete")) { card.delete() }
    }
}

private struct OptionalAction: ViewModifier {
    let name: LocalizedStringKey
    let isOffered: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isOffered {
            content.accessibilityAction(named: Text(name), action)
        } else {
            content
        }
    }
}
