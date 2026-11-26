// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What a locked collection shows until Face ID, Touch ID or the passcode opens it (ADR 0081).
struct LockedCollectionView: View {
    let collectionID: UUID
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        ContentUnavailableView {
            Label("This collection is locked", systemImage: "lock.fill")
        } description: {
            Text("Its clips show only here, after Face ID, Touch ID or your passcode.")
        } actions: {
            Button("Unlock") {
                Task {
                    _ = await appState.secretReveal.openCollection(
                        collectionID, reason: String(localized: "open a locked collection")
                    )
                }
            }
            .buttonStyle(.pestoProminent)
        }
    }
}
