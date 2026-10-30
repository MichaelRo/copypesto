// SPDX-License-Identifier: MIT
import SwiftUI

/// One number and what it counts, as a tile.
struct SettingsStat: Identifiable {
    let id: String
    let value: String
    let label: LocalizedStringKey
    var tint: Color?
}

/// A row of tiles that heads a pane with the facts it is about (Data: how many clips, how much disk, how old).
struct SettingsStatStrip: View {
    let stats: [SettingsStat]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: stat.value)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(stat.tint ?? Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(stat.label)
                        .font(.caption)
                        .pestoQuiet()
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.settingsChoice("stat", stat.id))
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    }
}
