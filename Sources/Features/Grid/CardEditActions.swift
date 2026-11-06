// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What the card's context menu edits, as VoiceOver actions too, for people who never open that menu. A modifier of its
/// own: the card's modifier chain is already at the type checker's limit.
struct CardEditActions: ViewModifier {
    let rename: () -> Void
    let addNote: () -> Void
    let addTag: () -> Void
    let offers: (CardMenuItem) -> Bool

    func body(content: Content) -> some View {
        content
            .accessibilityActions {
                if offers(.rename) { Button("Rename", action: rename) }
                if offers(.note) { Button("Add Note", action: addNote) }
                if offers(.tag) { Button("Add Tag", action: addTag) }
            }
    }
}
