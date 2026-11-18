// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct CardMenu: View {
    let card: ClipCard

    var body: some View {
        let item = card.item
        let concealment = card.concealment
        Button("Copy", systemImage: "doc.on.doc") { card.copy() }
        CopyActionsMenu(item: item)
        Button("Edit Details", systemImage: "info.circle") { card.library.open(item.id) }
        if !concealment.isConcealed {
            Button("Share", systemImage: "square.and.arrow.up") { card.share() }
        }
        Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") { card.togglePin() }
        AddToCollectionMenu(item: item, collections: card.collections)
        if card.appState.canSaveAsSnippet(item) {
            Button("Save as Snippet", systemImage: "text.badge.plus") {
                Task { await card.appState.saveAsSnippet(item) }
            }
        }
        if card.isCoveredForPrivacy
            || item.sensitivityRaw != nil && concealment.isConcealed && card.appState.secretReveal.canAuthenticate
        {
            Button("Show", systemImage: "eye") { card.show() }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { card.delete() }
    }
}

struct AddToCollectionMenu: View {
    let item: ClipboardItem
    let collections: [Pinboard]
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        let plain = collections.filter { !$0.isSmart }
        Menu("Add to Collection", systemImage: "folder.badge.plus") {
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
