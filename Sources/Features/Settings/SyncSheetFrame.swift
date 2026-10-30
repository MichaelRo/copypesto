// SPDX-License-Identifier: MIT
import SwiftUI

/// The chrome every sync sheet shares: a title, what to read, and the buttons.
struct SyncSheetFrame<Content: View, Actions: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold))
            content
            HStack {
                Spacer()
                actions
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

/// The words both Macs must show, large enough to read across a desk.
struct SyncWords: View {
    @Environment(\.pestoAccent) private var accent
    let words: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(accent.opacity(0.35)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words.joined(separator: ", "))
        .accessibilityIdentifier(AccessibilityID.syncPairingWords)
    }
}
