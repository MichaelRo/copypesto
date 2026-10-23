// SPDX-License-Identifier: MIT
import SwiftUI

/// Settings shows clip text, titles and app names in a few places (Most pasted, Snippets, pinned shortcuts,
/// collections).
/// While the History Lock is on and the history is locked, those places show an unlock prompt instead.
struct HistoryLockGate<Content: View>: View {
    @Environment(AppState.self) private var appState: AppState
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if appState.isHistoryLocked {
                VStack(alignment: .leading, spacing: 8) {
                    Label("History is locked", systemImage: "lock.fill")
                    Text("Unlock to see your clips here.").pestoCaption()
                    Button("Unlock") { Task { await appState.performBiometricUnlock() } }
                }
            } else {
                content()
            }
        }
        .onAppear { appState.checkAndApplyBiometricLock() }
    }
}
