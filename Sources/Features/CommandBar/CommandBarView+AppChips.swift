// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

extension CommandBarView {
    var appChips: [SourceApp] {
        AppChipsRow.chips(recent: suggestionsModel.suggestions.recentApps, frontmost: suggestionsModel.frontmost)
    }

    static let allChipID = AnyHashable("all-collections")

    /// Outside the scroll view, so the apps stay in reach however many collections push the row past the bar.
    var pinnedAppChips: some View {
        HStack(spacing: 6) {
            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)
            AppChipsRow(
                recent: suggestionsModel.suggestions.recentApps, frontmost: suggestionsModel.frontmost,
                collapsesLabels: !shownPinboards.isEmpty
            )
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App filters")
    }
}
