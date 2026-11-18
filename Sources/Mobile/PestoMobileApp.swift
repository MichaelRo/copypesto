// SPDX-License-Identifier: MIT
import AppIntents
import PestoCore
import SwiftUI

@main
struct PestoMobileApp: App {
    @State private var appState: MobileAppState
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let state = MobileAppState()
        _appState = State(initialValue: state)
        AppDependencyManager.shared.add(dependency: state)
        state.registerBackgroundRefresh()
    }

    var body: some Scene {
        WindowGroup {
            LibraryRootView()
                .environment(appState)
                .modifier(MobileAccent())
                .task {
                    appState.boot()
                    appState.lockDidBecomeActive()
                    appState.syncDidBecomeActive()
                    appState.inboxDidBecomeActive()
                    await appState.clipboardDidBecomeActive()
                }
                .defaultAppStorage(AppDefaults.store)
                .onOpenURL { appState.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await appState.sweepRetention() }
                appState.lockDidBecomeActive()
                appState.syncDidBecomeActive()
                appState.inboxDidBecomeActive()
                Task {
                    await appState.clipboardDidBecomeActive()
                    await appState.refreshWidgetPresence()
                }
            case .background:
                appState.didLeaveForeground()
                appState.syncDidEnterBackground()
            default: break
            }
        }
        .commands { LibraryCommands() }
    }
}
