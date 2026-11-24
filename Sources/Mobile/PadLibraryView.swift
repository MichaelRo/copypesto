// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The regular width: a sidebar of scopes and collections beside the grid, search in the top toolbar, and a clip's
/// detail in an inspector shown on demand. With the sidebar hidden the grid carries the chip row instead.
struct PadLibraryView: View {
    let store: HistoryStore
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]

    var body: some View {
        @Bindable var library = library
        NavigationSplitView(columnVisibility: $library.columns) {
            LibrarySidebar()
        } detail: {
            NavigationStack {
                LibraryGrid(
                    store: store,
                    showsChipRow: LibraryChrome.showsChipRow(
                        isRegular: true, columns: library.columns, isSearching: library.isSearching
                    ),
                    showsScopeChips: LibraryChrome.showsChipRow(isRegular: true, columns: library.columns)
                )
                .navigationTitle(LibraryTitle.text(for: library.filter.scope, collections: collections))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { LibraryToolbar(showsSettings: library.columns == .detailOnly) }
                .searchable(
                    text: $library.query, isPresented: $library.isSearching,
                    placement: .toolbar, prompt: Text("Search clips")
                )
                .onSubmit(of: .search) {
                    if AskHeuristic.returnAsks(text: library.query, resultCount: library.visibleResultCount) {
                        library.startAsk(
                            using: { await appState.askPesto($0) },
                            isLocked: { appState.isHistoryLockedNow() }
                        )
                    }
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command),
                          library.isSearching,
                          !library.query.trimmingCharacters(in: .whitespaces).isEmpty else { return .ignored }
                    library.startAsk(
                        using: { await appState.askPesto($0) },
                        isLocked: { appState.isHistoryLockedNow() }
                    )
                    return .handled
                }
                .onChange(of: library.query) { _, newValue in
                    if library.isAsking, newValue != library.activeAskSentence { library.cancelAsk() }
                }
            }
            .inspector(isPresented: inspectorBinding) {
                if let id = library.openClipID {
                    ClipDetailView(store: store, itemID: id, isSheet: false)
                        .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: library.isSearching) { _, searching in if !searching { library.endSearch() } }
        .libraryPresentations()
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(get: { library.openClipID != nil }, set: { if !$0 { library.openClipID = nil } })
    }
}
