// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The compact width: one stack with the chip row over the grid, search where iOS puts it for a single stack, and a
/// clip's detail in a sheet.
struct PhoneLibraryView: View {
    let store: HistoryStore
    @Environment(LibraryModel.self) private var library
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            LibraryGrid(store: store, showsChipRow: true)
                .navigationTitle(LibraryTitle.text(for: library.filter.scope, collections: collections))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { LibraryToolbar(showsSettings: true) }
        }
        .searchable(text: $library.query, isPresented: $library.isSearching, prompt: Text("Search clips"))
        .onChange(of: library.isSearching) { _, searching in if !searching { library.endSearch() } }
        .sheet(isPresented: detailBinding) {
            if let id = library.openClipID {
                ClipDetailView(store: store, itemID: id, isSheet: true)
                    .presentationDetents([.medium, .large])
            }
        }
        .libraryPresentations()
    }

    private var detailBinding: Binding<Bool> {
        Binding(get: { library.openClipID != nil }, set: { if !$0 { library.openClipID = nil } })
    }
}
