// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The Find bar's two side zones (design board 1b): on the left where you search (collections, then apps), on the
/// right every filter; each scrolls on its own and fades at its trailing edge, where it runs out of room.
extension CommandBarView {
    var searchScopeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                scrollableChips
                if !appChips.isEmpty { pinnedAppChips }
            }
            .padding(.vertical, 1)
        }
        .mask(Self.edgeFade(leading: false))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Collections and apps")
    }

    /// The chosen filters, shown as tokens in the field so they stay in view when their chips scroll away.
    var activeFilterTokens: [FilterEntry] {
        allFilterEntries.filter(\.isActive)
    }

    /// The chosen filters as tokens at the start of the field; a press takes one off.
    var filterTokens: some View {
        ForEach(activeFilterTokens, id: \.id) { entry in
            Button(action: entry.toggle) {
                HStack(spacing: 3) {
                    Text(entry.label)
                    Image(systemName: "xmark").imageScale(.small)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(accent)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove filter \(entry.spoken ?? entry.label)"))
        }
    }

    /// A mask that fades the last 12% of a strip at one edge.
    static func edgeFade(leading: Bool) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.88),
                .init(color: .clear, location: 1)
            ],
            startPoint: leading ? .trailing : .leading, endPoint: leading ? .leading : .trailing
        )
    }
}
