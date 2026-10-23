// SPDX-License-Identifier: MIT
import SwiftUI

/// What every Settings pane opens with: the pane's tile, its name, one sentence and, at the right, the pane's main
/// action. It sits above the pane's form, on the window's own ground, and stays put while the form scrolls.
struct SettingsPaneHeader<Accessory: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: Text
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(accent.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                subtitle
                    .font(.callout)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { accessory() }.fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

extension SettingsPaneHeader where Accessory == EmptyView {
    init(symbol: String, title: LocalizedStringKey, subtitle: Text) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension View {
    /// Pins a pane's header (and anything else that should stay in view) above its form. The form stays the pane's root
    /// view, so the toolbar and the sidebar behave as they do for any scrolling pane. The pinned area is opaque and
    /// ends in a hairline: rows scroll under an inset, so without a ground they showed through the header's text.
    func settingsPaneTop(@ViewBuilder _ top: () -> some View) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                top()
                Divider()
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
