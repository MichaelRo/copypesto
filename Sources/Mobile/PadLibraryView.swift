// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The regular-width layout: the scopes and collections, the clips of the chosen one, and the chosen clip.
struct PadLibraryView: View {
    let store: HistoryStore
    @Environment(MobileAppState.self) private var appState
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var scope: LibraryScope? = .all
    @State private var selectedClip: UUID?
    @State private var query = ""
    @State private var isNaming = false
    @State private var showsSettings = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
        } content: {
            let current = scope ?? .all
            ClipListView(
                store: store, scope: current, query: query, selection: $selectedClip,
                onSearch: { searchFocused = true }
            )
            .navigationTitle(title(for: current))
            .searchable(text: $query, prompt: Text("Search clips"))
            .searchFocused($searchFocused)
        } detail: {
            if let selectedClip {
                NavigationStack {
                    ClipDetailView(store: store, itemID: selectedClip) { self.selectedClip = nil }
                }
            } else {
                ContentUnavailableView("No Clip Selected", systemImage: "doc.on.clipboard")
                    .accessibilityIdentifier(MobileAccessibilityID.emptyDetail)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .libraryBanners()
        .onChange(of: scope) { selectedClip = nil }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSettings = false }
                        }
                    }
            }
        }
    }

    private var sidebar: some View {
        List(selection: $scope) {
            Section {
                Label(LibraryScope.all.title, systemImage: LibraryScope.all.symbolName).tag(LibraryScope.all)
                Label(LibraryScope.pinned.title, systemImage: LibraryScope.pinned.symbolName)
                    .tag(LibraryScope.pinned)
            }
            Section("Kinds") {
                ForEach(LibraryScope.filteredKinds, id: \.self) { kind in
                    Label(LibraryScope.kindTitle(kind), systemImage: kind.presentation.symbolName)
                        .tag(LibraryScope.kind(kind))
                }
            }
            Section("Collections") {
                ForEach(collections, id: \.id) { board in
                    CollectionLabel(board: board).tag(LibraryScope.collection(board.id))
                }
                Button("New Collection", systemImage: "plus") { isNaming = true }
            }
        }
        .accessibilityIdentifier(MobileAccessibilityID.sidebar)
        .navigationTitle("Pesto")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
            }
        }
        .newCollectionAlert(isPresented: $isNaming, existing: collections)
    }

    private func title(for scope: LibraryScope) -> String {
        if case let .collection(id) = scope {
            return collections.first { $0.id == id }?.name ?? scope.title
        }
        return scope.title
    }
}
