// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The compact layout: Library, Collections, Settings and Search tabs, each with its own navigation stack.
struct PhoneLibraryView: View {
    let store: HistoryStore

    private enum Pane: Hashable {
        case library, collections, settings, search
    }

    @State private var pane: Pane = .library
    @State private var scope: LibraryScope = .all
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        TabView(selection: $pane) {
            Tab("Library", systemImage: "tray.full", value: .library) {
                NavigationStack {
                    ClipListView(store: store, scope: scope, query: "", onSearch: openSearch)
                        .navigationTitle(scope.title)
                        .toolbar { scopeMenu }
                        .clipDestinations(store: store)
                }
                .libraryBanners()
            }
            Tab("Collections", systemImage: "folder", value: .collections) {
                NavigationStack {
                    CollectionsView(store: store)
                        .clipDestinations(store: store)
                }
                .libraryBanners()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
                    .libraryBanners()
            }
            Tab(value: .search, role: .search) {
                NavigationStack {
                    ClipListView(store: store, scope: .all, query: query, onSearch: openSearch)
                        .navigationTitle("Search")
                        .clipDestinations(store: store)
                }
                .searchable(text: $query, prompt: Text("Search clips"))
                .searchFocused($searchFocused)
                .libraryBanners()
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
    }

    private func openSearch() {
        pane = .search
        searchFocused = true
    }

    @ToolbarContentBuilder
    private var scopeMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu("Show", systemImage: "line.3.horizontal.decrease.circle") {
                Picker("Show", selection: $scope) {
                    Label(LibraryScope.all.title, systemImage: LibraryScope.all.symbolName).tag(LibraryScope.all)
                    Label(LibraryScope.pinned.title, systemImage: LibraryScope.pinned.symbolName)
                        .tag(LibraryScope.pinned)
                    ForEach(LibraryScope.filteredKinds, id: \.self) { kind in
                        Label(LibraryScope.kindTitle(kind), systemImage: kind.presentation.symbolName)
                            .tag(LibraryScope.kind(kind))
                    }
                }
            }
        }
    }
}

extension View {
    /// A pushed clip, and a pushed collection, in a compact navigation stack.
    func clipDestinations(store: HistoryStore) -> some View {
        modifier(ClipDestinations(store: store))
    }
}

private struct ClipDestinations: ViewModifier {
    let store: HistoryStore

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: ClipRoute.self) { route in
                PushedClipDetail(store: store, itemID: route.id)
            }
            .navigationDestination(for: CollectionRoute.self) { route in
                ClipListView(store: store, scope: .collection(route.id), query: "")
                    .navigationTitle(route.name)
            }
    }
}

private struct PushedClipDetail: View {
    let store: HistoryStore
    let itemID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ClipDetailView(store: store, itemID: itemID) { dismiss() }
    }
}
