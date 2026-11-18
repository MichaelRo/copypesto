// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

@main
struct PestoMobileApp: App {
    @State private var appState = MobileAppState()

    var body: some Scene {
        WindowGroup {
            LibraryRootView()
                .environment(appState)
                .task { appState.boot() }
        }
    }
}
