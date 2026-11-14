// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

@main
struct PestoMobileApp: App {
    @State private var appState = MobileAppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryRootView()
                .environment(appState)
                .modifier(MobileAccent())
                .task { appState.boot() }
                .defaultAppStorage(AppDefaults.store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { appState.didLeaveForeground() }
        }
        .commands { LibraryCommands() }
    }
}
