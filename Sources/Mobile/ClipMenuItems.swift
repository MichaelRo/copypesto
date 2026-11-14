// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The commands a clip offers, the same in a row's context menu and the detail view's More menu.
struct ClipMenuItems: View {
    let item: ClipboardItem
    let collections: [Pinboard]
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") { appState.copy(item) }
        Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
            let id = item.id
            Task { await appState.togglePin(id) }
        }
        MoveToCollectionMenu(item: item, collections: collections)
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            let id = item.id
            Task { await appState.delete([id]) }
        }
    }
}

struct MoveToCollectionMenu: View {
    let item: ClipboardItem
    let collections: [Pinboard]
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        let plain = collections.filter { !$0.isSmart }
        Menu("Move to Collection", systemImage: "folder") {
            ForEach(plain, id: \.id) { board in
                Button {
                    appState.moveToCollection(item, collectionID: board.id)
                } label: {
                    if item.collectionID == board.id {
                        Label(board.name, systemImage: "checkmark")
                    } else {
                        Text(board.name)
                    }
                }
            }
            if item.collectionID != nil {
                Divider()
                Button("Remove from Collection") { appState.moveToCollection(item, collectionID: nil) }
            }
        }
        .disabled(plain.isEmpty)
    }
}
