// SPDX-License-Identifier: MIT
import SwiftUI

/// A shortcut such as "⌘⇧V" drawn as one small key per symbol.
struct ShortcutKeycaps: View {
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(label.enumerated()), id: \.offset) { _, symbol in
                Keycap(symbol: String(symbol))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isStaticText)
    }
}
