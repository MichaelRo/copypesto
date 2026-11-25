// SPDX-License-Identifier: MIT
import SwiftUI

/// A Settings section's header in the Mac's language (`docs/design-language.md`, Settings): a tile with the section's
/// symbol in the accent on a 16% wash of it, then the title. Design board 5, 2026-11-25.
struct SettingsSectionHeader: View {
    let title: LocalizedStringKey
    let symbol: String
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                // A grouped Form draws a header in the secondary color unless the color is set outright.
                .foregroundStyle(Color(uiColor: .label))
        }
        .textCase(nil)
        .padding(.leading, -16)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Privacy's first row: what stays on this device, as the Mac's Privacy pane opens with its promise card. Information,
/// not a control.
struct PrivacyPromiseRow: View {
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        Text("Your clips are encrypted on this device. Only sync sends them, and only to your own folder.")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
            .listRowBackground(
                LinearGradient(
                    colors: [accent.opacity(0.12), accent.opacity(0)], startPoint: .topLeading, endPoint: .center
                )
                .background(Color(.secondarySystemGroupedBackground))
            )
    }
}
