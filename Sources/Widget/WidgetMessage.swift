// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

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

extension View {
    /// On the Mac a widget with no clip to show opens the shelf, which is also when Pesto asks whether a widget is
    /// installed (ADR 0059); on iOS a tap opens the app as it always has.
    @ViewBuilder
    func opensShelfOnTheMac() -> some View {
        #if os(macOS)
        widgetURL(URL(string: "\(AppIdentity.urlScheme)://open"))
        #else
        self
        #endif
    }

    @ViewBuilder
    func opensUnlockOnPhone() -> some View {
        #if !os(macOS)
        widgetURL(AppLink.url(for: .unlock))
        #else
        opensShelfOnTheMac()
        #endif
    }
}
