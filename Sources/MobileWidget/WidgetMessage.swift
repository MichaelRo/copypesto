// SPDX-License-Identifier: MIT
import SwiftUI

/// The widget with no clip to show: a symbol in the accent, one line, and on a wider widget a second.
struct WidgetMessage: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let compact: Bool

    var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: 6) {
            Image(systemName: symbol)
                .font(compact ? .title2 : .title)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(compact ? .leading : .center)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(compact ? .leading : .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .bottomLeading : .center)
        .accessibilityElement(children: .combine)
    }
}
