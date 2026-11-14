// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// A tab bar where the width is compact (iPhone, a narrow iPad window) and a split view where it is regular. The
/// size class decides, not the device, so an iPad in Split View or Stage Manager gets the layout that fits.
struct LibraryRootView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if let container = appState.historyContainer, let store = appState.historyStore {
            Group {
                if sizeClass == .regular {
                    PadLibraryView(store: store)
                } else {
                    PhoneLibraryView(store: store)
                }
            }
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
