// SPDX-License-Identifier: MIT
import SwiftUI

/// The question before clips are removed, drawn inside the shelf. A system alert sits in a window that never becomes
/// key while the shelf (a non-activating panel) is up, so Return did nothing until the alert was clicked; here the
/// shelf's own key handling answers it (`KeyNavCoordinator.isConfirming`): Return deletes, Esc keeps.
struct ShelfDeleteConfirmation: View {
    let count: Int
    /// Whether ⌘Z will be able to bring them back (`UndoPolicy`), which the question says either way.
    let canUndo: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    /// Moves VoiceOver onto the question, as the lock screen does, so the Return that follows is not a surprise.
    @AccessibilityFocusState private var isFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var title: String {
        count == 1 ? String(localized: "Delete this clip?") : String(localized: "Delete \(CountText.clips(count))?")
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.statusBad)
                .accessibilityHidden(true)
            Text(title)
                .scaledFont(size: 13, weight: .semibold)
            Text(count == 1
                ? "This removes the clip from your clipboard history."
                : "This removes them from your clipboard history.")
                .scaledFont(size: 11)
                .pestoQuiet()
                .multilineTextAlignment(.center)
            Text(canUndo
                ? "You can undo this with \u{2318}Z."
                : "This can\u{2019}t be undone.")
                .scaledFont(size: 11)
                .foregroundStyle(AdaptiveContrast.quiet(contrast))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.pestoCapsule(.secondary))
                    .accessibilityIdentifier(AccessibilityID.deleteCancelButton)
                Button(role: .destructive, action: onConfirm) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.pestoCapsule(.confirmDestructive))
                .accessibilityIdentifier(AccessibilityID.deleteConfirmButton)
            }
            HStack(spacing: 5) {
                Keycap(symbol: "return", size: .compact, solid: true)
                Text("to delete")
                Keycap(symbol: "esc", size: .compact, solid: true).padding(.leading, 6)
                Text("to keep")
            }
            .scaledFont(size: 11, maxScale: 1.3)
            .foregroundStyle(.primary)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel("Return to delete, Escape to keep")
        }
        .padding(20)
        .frame(width: 300)
        // Solid, not material: over the cards behind it every line of text failed the contrast audit in light mode.
        .background(Color.opaqueSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(title)
        .accessibilityFocused($isFocused)
        .onAppear {
            isFocused = true
            Announcer.announce(String(localized: "\(title) Return deletes, Escape keeps."))
        }
    }
}
