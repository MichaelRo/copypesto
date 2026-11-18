// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// One clip whole, in a sheet on a compact width and in the inspector on a regular one: its content at full size, its
/// title, note and tags edited in place, its collection and one line of facts, with Copy and Share in the toolbar.
struct ClipDetailView: View {
    let store: HistoryStore
    let itemID: UUID
    let isSheet: Bool

    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.pestoSurface) private var ground
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var content: ClipContent?
    @State private var revealedText: String?
    @State private var isEditingText = false

    var body: some View {
        NavigationStack {
            Group {
                if let item = store.item(for: itemID) {
                    detail(item)
                } else {
                    ContentUnavailableView("Clip Deleted", systemImage: "trash")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) { if isSheet { LibraryBanners() } }
            .sheet(item: fillBinding) { request in
                SnippetFillSheet(request: request).presentationDetents([.medium, .large])
            }
        }
    }

    private var fillBinding: Binding<SnippetFillRequest?> {
        Binding(get: { isSheet ? appState.pendingFill : nil }, set: { appState.pendingFill = $0 })
    }

    private func detail(_ item: ClipboardItem) -> some View {
        let concealment = appState.secretReveal.concealment(for: item)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isEditingText, let text = content?.plainText {
                    ClipTextEditor(item: item, text: text) { isEditingText = false }
                } else {
                    if appState.canEditText(item), content?.plainText != nil {
                        Button("Edit Text", systemImage: "pencil") { isEditingText = true }
                            .accessibilityIdentifier(MobileAccessibilityID.editTextButton)
                    }
                    ClipBodyView(item: item, content: content, concealment: concealment, revealedText: revealedText)
                        .accessibilityIdentifier(MobileAccessibilityID.clipDetailBody)
                }
                if item.sensitivityRaw != nil,
                   !appState.secretReveal.isCoveredForPrivacy(item.id) { revealControl(item) }
                ClipDetailFields(item: item).id(item.id)
                AddToCollectionMenu(item: item, collections: collections)
                    .buttonStyle(MobileChipStyle(isActive: item.collectionID != nil, tint: nil))
                factsLine(item, concealment: concealment)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ground.ignoresSafeArea())
        .accessibilityIdentifier(MobileAccessibilityID.clipDetail)
        .navigationTitle(item.type.presentation.label)
        .toolbar { toolbar(item, concealment: concealment) }
        .task(id: TaskKey(id: item.id, covered: concealment.isConcealed, content: item.contentHash)) {
            content = concealment.isConcealed ? nil : ClipContent.of(item)
            revealedText = appState.secretReveal.isShown(item.id)
                ? HiddenClipReveal.readableText(from: item.blob?.decryptedData()) : nil
        }
        .onChange(of: appState.secretReveal.isShown(item.id)) { _, shown in
            revealedText = shown ? HiddenClipReveal.readableText(from: item.blob?.decryptedData()) : nil
            if !shown { isEditingText = false }
        }
        .onChange(of: itemID) { _, _ in isEditingText = false }
    }

    private struct TaskKey: Hashable {
        let id: UUID
        let covered: Bool
        let content: String
    }

    private func factsLine(_ item: ClipboardItem, concealment: CardConcealment) -> some View {
        let name = item.collectionID.flatMap { id in collections.first { $0.id == id }?.name }
        let facts = ClipFacts.facts(for: item, collectionName: name, isShown: !concealment.isConcealed)
        return Text(facts.map { ClipFacts.text(for: $0) }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func revealControl(_ item: ClipboardItem) -> some View {
        if appState.secretReveal.isShown(item.id) {
            Button("Hide", systemImage: "eye.slash") { appState.secretReveal.hide(item.id) }
        } else if appState.secretReveal.canAuthenticate {
            Button("Show", systemImage: "eye") {
                let id = item.id
                Task { await appState.secretReveal.show(id, reason: String(localized: "Show the hidden clip")) }
            }
        } else {
            Text("Set a passcode on this device to show hidden clips. Copy still works.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ item: ClipboardItem, concealment: CardConcealment) -> some ToolbarContent {
        if isSheet {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { library.openClipID = nil }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc") {
                if appState.copy(item) { library.didCopy(item.id) }
            }
            .accessibilityIdentifier(MobileAccessibilityID.copyButton)
            if let content, !concealment.isConcealed {
                ShareLink(item: ClipTransfer(content: content), preview: SharePreview(item.type.presentation.label))
            }
            Menu("More", systemImage: "ellipsis") {
                Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                    let id = item.id
                    Task { await appState.togglePin(id) }
                }
                CopyActionsMenu(item: item)
                if appState.canSaveAsSnippet(item) {
                    Button("Save as Snippet", systemImage: "text.badge.plus") {
                        Task { await appState.saveAsSnippet(item) }
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    let id = item.id
                    library.openClipID = nil
                    Task { await appState.delete([id]) }
                }
            }
        }
    }
}
