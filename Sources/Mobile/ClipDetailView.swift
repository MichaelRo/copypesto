// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// One clip whole: its content, its title, note and tags, its facts, and what can be done with it.
struct ClipDetailView: View {
    let store: HistoryStore
    let itemID: UUID
    var onDeleted: () -> Void = {}

    @Environment(MobileAppState.self) private var appState
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var content: ClipContent?
    @State private var revealedText: String?
    @State private var isEditing = false

    var body: some View {
        if let item = store.item(for: itemID) {
            detail(item)
        } else {
            ContentUnavailableView("Clip Deleted", systemImage: "trash")
        }
    }

    private func detail(_ item: ClipboardItem) -> some View {
        let concealment = appState.secretReveal.concealment(for: item)
        return List {
            Section {
                ClipBodyView(item: item, content: content, concealment: concealment, revealedText: revealedText)
                    .accessibilityIdentifier(MobileAccessibilityID.clipDetailBody)
                    .modifier(ClipDragSource(
                        transfer: concealment.allowsDrag ? content.map(ClipTransfer.init) : nil,
                        label: item.type.presentation.label, symbolName: item.type.presentation.symbolName
                    ))
                if item.sensitivityRaw != nil {
                    revealControl(item)
                }
            }
            ClipInfoSection(item: item, isEditing: $isEditing)
            Section("Details") {
                let name = item.collectionID.flatMap { id in collections.first { $0.id == id }?.name }
                ForEach(
                    Array(ClipFacts.facts(for: item, collectionName: name, isShown: !concealment.isConcealed)
                        .enumerated()),
                    id: \.offset
                ) { _, fact in
                    Text(ClipFacts.text(for: fact))
                }
            }
        }
        .accessibilityIdentifier(MobileAccessibilityID.clipDetail)
        .navigationTitle(item.type.presentation.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(item, concealment: concealment) }
        .sheet(isPresented: $isEditing) { ClipEditView(item: item) }
        .task(id: TaskKey(id: item.id, covered: concealment.isConcealed)) {
            content = concealment.isConcealed ? nil : ClipContent.of(item)
        }
        .onChange(of: appState.secretReveal.isShown(item.id)) { _, shown in
            if !shown { revealedText = nil }
        }
        .focusedSceneValue(\.clipCommands, ClipCommandActions(
            isPinned: item.isPinned,
            copy: { appState.copy(item) },
            togglePin: { Task { await appState.togglePin(itemID) } },
            delete: { delete() }
        ))
    }

    private struct TaskKey: Hashable {
        let id: UUID
        let covered: Bool
    }

    @ViewBuilder
    private func revealControl(_ item: ClipboardItem) -> some View {
        if appState.secretReveal.isShown(item.id) {
            Button("Hide", systemImage: "eye.slash") { appState.secretReveal.hide(item.id) }
        } else if appState.secretReveal.canAuthenticate {
            Button("Show", systemImage: "eye") { show(item) }
        } else {
            Text("Set a passcode on this device to show hidden clips. Copy still works.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func show(_ item: ClipboardItem) {
        Task {
            guard await appState.secretReveal.show(item.id, reason: String(localized: "Show the hidden clip")) else {
                return
            }
            revealedText = HiddenClipReveal.readableText(from: item.blob?.decryptedData())
        }
    }

    private func delete() {
        Task {
            await appState.delete([itemID])
            onDeleted()
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ item: ClipboardItem, concealment: CardConcealment) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc") { appState.copy(item) }
                .accessibilityIdentifier(MobileAccessibilityID.copyButton)
            if let content, !concealment.isConcealed {
                ShareLink(
                    item: ClipTransfer(content: content),
                    preview: SharePreview(item.type.presentation.label)
                )
            }
            Menu("More", systemImage: "ellipsis.circle") {
                Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                    Task { await appState.togglePin(itemID) }
                }
                MoveToCollectionMenu(item: item, collections: collections)
                Button("Edit Details", systemImage: "pencil") { isEditing = true }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { delete() }
            }
        }
    }
}

/// A clip that is not covered can be dragged out of Pesto (on iPad, into another app); a covered one cannot (ADR 0003).
private struct ClipDragSource: ViewModifier {
    let transfer: ClipTransfer?
    let label: String
    let symbolName: String

    func body(content: Content) -> some View {
        if let transfer {
            content.draggable(transfer) { Label(label, systemImage: symbolName) }
        } else {
            content
        }
    }
}
