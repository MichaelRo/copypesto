// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// The page buttons of a medium widget (a narrow column at the trailing edge) or a large one (a strip at the bottom),
/// shown only while there is more than one page (ADR 0067). Each button runs `ShowClipPageIntent`; the dots say where
/// the widget is.
struct WidgetPageControl: View {
    let key: String
    let page: Int
    let pageCount: Int
    let snapshotCreatedAt: Date
    let isVertical: Bool

    var body: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            button(step: -1, symbol: isVertical ? "chevron.up" : "chevron.backward", label: "Previous Clips")
            dots
            button(step: 1, symbol: isVertical ? "chevron.down" : "chevron.forward", label: "Next Clips")
        }
        .frame(maxWidth: isVertical ? nil : .infinity, maxHeight: isVertical ? .infinity : nil)
    }

    private var dots: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 5, height: 5)
            }
        }
        .widgetAccentable()
        .invalidatableContent()
        .accessibilityHidden(true)
    }

    private func button(step: Int, symbol: String, label: LocalizedStringKey) -> some View {
        Button(intent: ShowClipPageIntent(
            key: key, step: step, page: page, pageCount: pageCount, snapshotCreatedAt: snapshotCreatedAt
        )) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .widgetAccentable()
        .accessibilityLabel(Text(label))
    }
}
