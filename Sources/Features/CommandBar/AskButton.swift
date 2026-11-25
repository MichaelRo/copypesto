// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Ask beside the Find field, as the iPhone's Ask chip: offered for any typed text, drawn forward in the accent when
/// the text reads like a question, with its shortcut (⌘Return) on it and a spinner while Pesto works.
struct AskButton: View {
    let isQuestion: Bool
    let isAsking: Bool
    let action: () -> Void
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isAsking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "sparkles").accessibilityHidden(true)
                }
                Text("Ask")
                Text("⌘↩")
                    .font(.subheadline)
                    .pestoQuiet()
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(isQuestion ? accent : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule().strokeBorder(isQuestion ? accent.opacity(0.45) : .clear, lineWidth: 1)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(isAsking)
        .help("Turn this into filters (⌘Return)")
        .accessibilityLabel("Ask Pesto")
        .accessibilityHint("Turns what you typed into filters.")
        .accessibilityIdentifier(AccessibilityID.askButton)
    }
}
