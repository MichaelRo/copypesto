// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The rest of what the context menu offers, as VoiceOver actions: pin, open a link, remove a tag, and tell the person
/// which clip the arrow keys moved to. A modifier of its own for the same reason as `CardEditActions`.
struct CardMoreActions: ViewModifier {
    let isPinned: Bool
    let togglePin: (() -> Void)?
    let openLink: LinkOpenPolicy.Action
    let tags: [String]
    let removeTag: (String) -> Void
    let isFocused: Bool
    let spokenCard: String

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: isPinned ? "Unpin" : "Pin") { togglePin?() }
            .accessibilityActions {
                if let title = LinkOpener.title(for: openLink) {
                    Button(title) { LinkOpener.perform(openLink) }
                }
            }
            .accessibilityActions {
                ForEach(tags, id: \.self) { tag in
                    Button("Remove Tag \(tag)") { removeTag(tag) }
                }
            }
            .onChange(of: isFocused) { _, focused in
                guard focused, NSWorkspace.shared.isVoiceOverEnabled else { return }
                Announcer.announce(spokenCard)
            }
    }
}
