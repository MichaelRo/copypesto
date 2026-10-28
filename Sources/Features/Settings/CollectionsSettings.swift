// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Settings → Collections: the collections on the shelf, in order, and the ones Pesto suggests.
struct CollectionsSettings: View {
    @Environment(AppState.self) private var appState: AppState
    @State private var addRequest = 0
    @State private var importRequest = 0

    private var canEdit: Bool {
        appState.historyContainer != nil && !appState.isHistoryLocked
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                symbol: "tray.2", title: "Collections",
                subtitle: Text("Group clips on the shelf. A smart collection fills itself.")
            ) {
                HStack(spacing: 8) {
                    Button("Import\u{2026}") { importRequest += 1 }
                        .buttonStyle(.bordered)
                        .disabled(!canEdit)
                    Button("Add Collection", systemImage: "plus") { addRequest += 1 }
                        .buttonStyle(.pestoProminent)
                        .disabled(!canEdit)
                }
            }
            if let container = appState.historyContainer {
                HistoryLockGate {
                    CollectionListView(addRequest: addRequest, importRequest: importRequest)
                        .modelContainer(container)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Collections unavailable",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("Storage is not available. Restart Pesto and try again.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Settings → Snippets: text you paste again and again, with the date, a name or a choice filled in.
struct SnippetsSettings: View {
    @Environment(AppState.self) private var appState: AppState
    @State private var addRequest = 0

    private var canEdit: Bool {
        appState.historyContainer != nil && !appState.isHistoryLocked
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                symbol: "curlybraces", title: "Snippets",
                subtitle: Text("Text you paste again and again, with the date, a name or a choice filled in.")
            ) {
                Button("Add Snippet", systemImage: "plus") { addRequest += 1 }
                    .buttonStyle(.pestoProminent)
                    .disabled(!canEdit)
            }
            if let container = appState.historyContainer {
                HistoryLockGate { SnippetsView(addRequest: addRequest).modelContainer(container) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Snippets unavailable",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("Storage is not available. Restart Pesto and try again.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
