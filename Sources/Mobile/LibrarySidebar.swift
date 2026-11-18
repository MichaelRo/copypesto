// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

struct LibrarySidebar: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]

    var body: some View {
        List(selection: selection) {
            Label(LibraryScope.all.title, systemImage: LibraryScope.all.symbolName).tag(LibraryScope.all)
            Label(LibraryScope.pinned.title, systemImage: LibraryScope.pinned.symbolName).tag(LibraryScope.pinned)
            Section("Collections") {
                ForEach(collections, id: \.id) { board in
                    collectionRow(board)
                }
                Button("New Collection", systemImage: "plus") { library.isNamingCollection = true }
            }
        }
        .accessibilityIdentifier(MobileAccessibilityID.sidebar)
        .navigationTitle("Pesto")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Settings", systemImage: "gearshape") { library.showsSettings = true }
                    .accessibilityIdentifier(MobileAccessibilityID.settingsButton)
            }
        }
    }

    private var selection: Binding<LibraryScope?> {
        Binding(
            get: { library.filter.scope },
            set: { scope in if let scope { library.filter.scope = scope } }
        )
    }

    private func collectionRow(_ board: Pinboard) -> some View {
        Label {
            Text(board.name)
        } icon: {
            Image(systemName: board.isSmart ? "sparkles" : board.symbolName)
                .foregroundStyle(Color(hex: board.colorHex) ?? .secondary)
        }
        .tag(LibraryScope.collection(board.id))
        .contextMenu { CollectionMenu(board: board) }
        .onDrop(of: [ClipDrag.clipIDType], isTargeted: nil) { providers in
            guard !board.isSmart else { return false }
            Task { await file(providers, into: board.id) }
            return true
        }
    }

    private func file(_ providers: [NSItemProvider], into collectionID: UUID) async {
        guard let id = await ClipDrag.clipID(in: providers), let item = appState.historyStore?.item(for: id) else {
            return
        }
        appState.moveToCollection(item, collectionID: collectionID)
    }
}

struct CollectionMenu: View {
    let board: Pinboard
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Button("Rename", systemImage: "pencil") { library.renaming = board }
        Button("Delete Collection", systemImage: "trash", role: .destructive) {
            let id = board.id
            Task { await appState.deleteCollection(id) }
        }
    }
}
