// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

@main
struct PestoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .defaultAppStorage(AppDefaults.store)
                .environment(appDelegate.appState)
                .modelContainerIfAvailable(appDelegate.appState.historyContainer)
        }
    }
}

// MARK: - Conditional model container injection

private extension View {
    @ViewBuilder
    func modelContainerIfAvailable(_ container: ModelContainer?) -> some View {
        if let container {
            self.modelContainer(container)
        } else {
            self
        }
    }
}
