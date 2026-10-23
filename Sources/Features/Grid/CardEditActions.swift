// SPDX-License-Identifier: MIT
import SwiftUI

/// What the card's context menu edits, as VoiceOver actions too, for people who never open that menu. A modifier of its
/// own: the card's modifier chain is already at the type checker's limit.
struct CardEditActions: ViewModifier {
    let rename: () -> Void
    let addNote: () -> Void
    let addTag: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: "Rename", rename)
            .accessibilityAction(named: "Add Note", addNote)
            .accessibilityAction(named: "Add Tag", addTag)
    }
}
