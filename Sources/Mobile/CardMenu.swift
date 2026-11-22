// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct CardMenu: View {
    let card: ClipCard

    var body: some View {
        let item = card.item
        let concealment = card.concealment
        Button("Copy", systemImage: "doc.on.doc") { card.copy() }
        if !concealment.isConcealed, item.type == .url,
           case let .openInBrowser(url) = LinkOpenPolicy.action(for: item.displayPreviewText)
        {
            Button("Open Link", systemImage: "safari") { card.appState.openExternally(url) }
        }
        CopyActionsMenu(item: item)
        if !concealment.isConcealed, item.type == .url, item.sensitivityRaw == nil {
            if let pageTitle = item.ogTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !pageTitle.isEmpty {
                Button("Copy Page Title", systemImage: "text.quote") {
                    if card.appState.copyPageTitle(item) { card.library.didCopy(item.id) }
                }
            }
            if LinkPreviewImageStore().load(for: item.id) != nil {
                Button("Copy Preview Image", systemImage: "photo") {
                    if card.appState.copyLinkPreviewImage(item) { card.library.didCopy(item.id) }
                }
            }
        }
        AIActionsMenu(item: item)
        if card.appState.canEditText(item), let text = ClipContent.of(item)?.plainText {
            Button("Edit Text\u{2026}", systemImage: "pencil") {
                card.library.beginTextEdit(of: item.id, text: text)
                card.library.open(item.id)
            }
        }
        Button("Edit Details", systemImage: "info.circle") { card.library.open(item.id) }
        if !concealment.isConcealed {
            Button("Share", systemImage: "square.and.arrow.up") { card.share() }
        }
        Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") { card.togglePin() }
        AddToCollectionMenu(item: item, collections: card.collections)
        if card.appState.canEditSnippet(item), let text = ClipContent.of(item)?.plainText {
            Button("Edit Snippet\u{2026}", systemImage: "curlybraces") {
                card.library.beginSnippetEdit(of: item, text: text)
            }
        }
        if card.appState.canSaveAsSnippet(item) {
            Button("Save as Snippet", systemImage: "text.badge.plus") {
                Task { await card.appState.saveAsSnippet(item) }
            }
        }
        if card.isCoveredForPrivacy
            || (concealment.isNSFWBlurred && !card.isCoveredForPrivacy)
            || item.sensitivityRaw != nil && concealment.isConcealed && card.appState.secretReveal.canAuthenticate
        {
            Button("Show", systemImage: "eye") { card.show() }
        } else if (item.sensitivityRaw != nil && card.appState.secretReveal.isShown(item.id))
            || (item.isNSFW && card.appState.secretReveal.isNSFWShown(item.id))
        {
            Button("Hide", systemImage: "eye.slash") { card.hide() }
        }
        if !concealment.isConcealed, item.sensitivityRaw == nil, item.type == .image || item.type == .url {
            Button(
                item.isNSFW ? "Mark as Not Sensitive" : "Mark as Sensitive",
                systemImage: item.isNSFW ? "eye" : "eye.slash"
            ) {
                card.appState.secretReveal.hideNSFW(item.id)
                card.appState.toggleSensitive(item)
            }
        }
        Button("Select Clips", systemImage: "checkmark.circle") {
            card.library.beginSelection(with: item.id)
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
