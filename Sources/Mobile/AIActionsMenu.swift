// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// AI Actions in a clip's menus: the on-device model's actions for the clip, greyed out with the reason when it
/// cannot run, and not there at all when it never can on this device (ADR 0005).
struct AIActionsMenu: View {
    let item: ClipboardItem
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        let offer = appState.aiOffer(for: item)
        if !offer.isEmpty {
            Menu("AI Actions", systemImage: "sparkles") {
                if let reason = offer.reason {
                    Section(reason) { rows(offer) }
                } else {
                    rows(offer)
                }
            }
            .accessibilityIdentifier(MobileAccessibilityID.aiActionsMenu)
        }
    }

    private func rows(_ offer: CardAIActions.Offer) -> some View {
        ForEach(offer.actions, id: \.self) { action in
            Button {
                appState.runAIAction(action, on: item)
            } label: {
                Label {
                    Text(action.title)
                } icon: {
                    Image(systemName: action.symbolName)
                }
            }
            .disabled(!offer.isEnabled)
        }
    }
}
