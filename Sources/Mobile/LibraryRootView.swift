// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// One page for the library and search. The width decides the frame, not the device: a compact width (an iPhone, an
/// iPad in a narrow window) gets one navigation stack with the chip row, a regular one a sidebar beside the grid.
struct LibraryRootView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var library = LibraryModel()

    var body: some View {
        if let container = appState.historyContainer, let store = appState.historyStore {
            Group {
                if sizeClass == .regular {
                    PadLibraryView(store: store)
                } else {
                    PhoneLibraryView(store: store)
                }
            }
            .environment(library)
            .modelContainer(container)
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
