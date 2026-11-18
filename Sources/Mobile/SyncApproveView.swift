// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A device asks to join: allow it only when its screen shows the same eight words.
struct SyncApproveView: View {
    let sync: MobileSync
    let pending: SyncPendingJoin

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Allow it only if the other device shows the same words. " +
                            "It will be able to read your synced clips."
                    )
                    SyncWordsGrid(words: pending.words)
                }
            }
            .navigationTitle(String(localized: "\u{201C}\(pending.request.name)\u{201D} Wants to Join"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Don\u{2019}t Allow") { sync.deny(pending) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Allow") { sync.approve(pending) }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
