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
    @State private var library: LibraryModel
    @State private var width: CGFloat = 0
    @State private var automaticColumns: NavigationSplitViewVisibility?

    init(library: LibraryModel = LibraryModel()) {
        _library = State(initialValue: library)
    }

    private var layoutSizeClass: UserInterfaceSizeClass? {
        #if DEBUG
        library.forcedSizeClass ?? sizeClass
        #else
        sizeClass
        #endif
    }

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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0
                decideColumns()
            }
            .onChange(of: layoutSizeClass) { _, _ in
                automaticColumns = nil
                decideColumns()
            }
        #if DEBUG
            .overlay(alignment: .bottomLeading) { UITestLayout.swapControl(library: library, actual: sizeClass) }
        #endif
            .background(SceneCaptureReader { appState.secretReveal.isScreenCaptured = $0 || Self.forcesSceneCapture })
            .background(PrivacyCoverHost(covers: PrivacyCoverHost.covers(
                in: scenePhase,
                isLocked: appState.isHistoryLocked
            )))
            .modifier(WelcomePresentation(onDismiss: startRequestedSync))
            .onChange(of: appState.hasBooted, initial: true) { _, booted in
                if booted { appState.presentWelcomeOnFirstLaunch() }
            }
            .animation(Motion.animation(.pestoWash), value: appState.isHistoryLocked)
            .onChange(of: appState.isHistoryLocked) { _, locked in if locked { library.closeEverything() } }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isHistoryLocked {
            LockScreenView().transition(.opacity)
        } else if let container = appState.historyContainer, let store = appState.historyStore {
            Group {
                if layoutSizeClass == .regular {
                    // Built only once the width has decided the columns: built with the default and changed after
                    // the first layout, the split view's pending transition wrote the sidebar back as shown.
                    if width > 0 { PadLibraryView(store: store) } else { Color.clear }
                } else {
                    PhoneLibraryView(store: store)
                }
            }
            .environment(library)
            .modifier(ForcedSizeClass(forced: library.forcedSizeClassIfDebug, actual: sizeClass))
            .modelContainer(container)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .onChange(of: scenePhase) { _, phase in if phase == .active { library.resort() } }
            .onChange(of: appState.linkedClip) { _, linked in if let linked { library.show(
                linked.id,
                opensDetail: linked.opensDetail
            ) } }
            .onChange(of: appState.shortcutSearchQuery, initial: true) { _, pending in
                guard pending != nil, let query = appState.takeShortcutSearchQuery() else { return }
                library.openSearch(query)
            }
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

extension LibraryRootView {
    /// Turn On Sync in the welcome: the library opens the sync flow once the welcome has gone.
    private func startRequestedSync() {
        guard appState.takeSyncSetUpRequest(), let sync = appState.sync else { return }
        if sync.canBeginSetUp { sync.beginSetUp() } else { library.picksSyncFolder = true }
    }

    /// A regular width starts with the sidebar shown or hidden by how wide the window is, and follows the width until
    /// the person shows or hides the sidebar themselves. A compact width keeps them decided too, so a change to regular
    /// (unfolding, a wider Split View) builds the split view with them instead of changing them under it.
    private func decideColumns() {
        guard width > 0 else { return }
        guard automaticColumns == nil || library.columns == automaticColumns else { return }
        let wanted = LibraryChrome.initialColumns(width: width)
        automaticColumns = wanted
        library.columns = wanted
    }
}

private struct ForcedSizeClass: ViewModifier {
    let forced: UserInterfaceSizeClass?
    let actual: UserInterfaceSizeClass?

    func body(content: Content) -> some View {
        if let forced, forced != actual {
            content.environment(\.horizontalSizeClass, forced)
        } else {
            content
        }
    }
}
