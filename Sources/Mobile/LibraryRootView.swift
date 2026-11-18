// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// One page for the library and search. The width decides the frame, not the device: a compact width (an iPhone, an
/// iPad in a narrow window) gets one navigation stack with the chip row, a regular one a sidebar beside the grid.
struct LibraryRootView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var library = LibraryModel()

    /// A `-UITestMode` launch can say the scene is being captured, since a simulator never reports a real capture.
    private static var forcesSceneCapture: Bool {
        #if DEBUG
        LaunchMode.current == .uiTest && AppDefaults.store.value(for: Setting.uitestForcesSceneCapture)
        #else
        false
        #endif
    }

    var body: some View {
        content
            .background(SceneCaptureReader { appState.secretReveal.isScreenCaptured = $0 || Self.forcesSceneCapture })
            .background(PrivacyCoverHost(covers: PrivacyCoverHost.covers(in: scenePhase)))
            .animation(Motion.animation(.pestoWash), value: appState.isHistoryLocked)
            .onChange(of: appState.isHistoryLocked) { _, locked in if locked { library.closeEverything() } }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isHistoryLocked {
            LockScreenView().transition(.opacity)
        } else if let container = appState.historyContainer, let store = appState.historyStore {
            Group {
                if sizeClass == .regular {
                    PadLibraryView(store: store)
                } else {
                    PhoneLibraryView(store: store)
                }
            }
            .environment(library)
            .modelContainer(container)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .onChange(of: scenePhase) { _, phase in if phase == .active { library.resort() } }
            .onChange(of: appState.linkedClip) { _, linked in if let linked { library.show(
                linked.id,
                opensDetail: linked.opensDetail
            ) } }
        } else if appState.hasBooted {
            ContentUnavailableView(
                "History Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Pesto could not open its history. Restart Pesto to try again.")
            )
        } else {
            ProgressView()
        }
    }
}
