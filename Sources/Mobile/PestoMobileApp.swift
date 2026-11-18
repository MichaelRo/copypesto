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
                .task {
                    appState.boot()
                    appState.syncDidBecomeActive()
                }
                .defaultAppStorage(AppDefaults.store)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: appState.syncDidBecomeActive()
            case .background:
                appState.didLeaveForeground()
                appState.syncDidEnterBackground()
            default: break
            }
        }
        .commands { LibraryCommands() }
    }
}
