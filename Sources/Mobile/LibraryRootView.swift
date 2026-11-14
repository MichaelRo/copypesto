// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct LibraryRootView: View {
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pesto")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let store = appState.historyStore {
            ClipList(store: store, isOnDisk: appState.storeIsOnDisk)
        } else if appState.hasBooted {
            ContentUnavailableView(
                "History Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Pesto could not open its history. Restart the app to try again.")
            )
        } else {
            ProgressView()
        }
    }
}

private struct ClipList: View {
    let store: HistoryStore
    let isOnDisk: Bool

    var body: some View {
        List {
            if !isOnDisk {
                Label(
                    "Nothing is saved this session: the history could not be opened on disk.",
                    systemImage: "bolt.slash"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            ForEach(store.items, id: \.id) { item in
                Text(item.gridPreview)
                    .lineLimit(3)
                    .accessibilityIdentifier("clip-row")
            }
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView(
                    "No Clips Yet",
                    systemImage: "doc.on.clipboard",
                    description: Text("Clips you add here, or copy on a Mac that syncs, appear in this list.")
                )
            }
        }
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }
}
