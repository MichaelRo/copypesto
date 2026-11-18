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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var content: ClipContent?
    @State private var revealedText: String?

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
            .clipResultSheets(.detail)
            #if DEBUG
                .overlay(alignment: .top) {
                    UITestLayout.swapControl(
                        library: library, actual: sizeClass, identifier: UITestLayout.detailSwapIdentifier
                    )
                    .padding(.top, 90)
                }
            #endif
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
                if isEditingText(item), content?.plainText != nil {
                    ClipTextEditor(item: item, onClose: { library.endTextEdit() }, draft: draftBinding)
                } else {
                    if appState.canEditText(item), let text = content?.plainText {
                        Button("Edit Text", systemImage: "pencil") { library.beginTextEdit(of: item.id, text: text) }
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
            .animation(Motion.animation(.pestoQuick), value: isEditingText(item))
        }
        .background(ground.ignoresSafeArea())
        .accessibilityIdentifier(MobileAccessibilityID.clipDetail)
        .navigationTitle(item.type.presentation.label)
        .toolbar { toolbar(item, concealment: concealment) }
        .task(id: TaskKey(id: item.id, covered: concealment.isConcealed, content: item.contentHash)) {
            let id = item.id
            guard let container = appState.historyContainer else { return }
            content = concealment.isConcealed || item.type == .image
                ? nil : await ClipContent.load(itemID: id, container: container)
            revealedText = await revealed(id, isShown: appState.secretReveal.isShown(id), container: container)
        }
        .onChange(of: appState.secretReveal.isShown(item.id)) { _, shown in
            if !shown { library.endTextEdit() }
            guard let container = appState.historyContainer else { return }
            let id = item.id
            Task { revealedText = await revealed(id, isShown: shown, container: container) }
        }
        .onChange(of: itemID) { _, id in if !library.isEditingText(of: id) { library.endTextEdit() } }
    }

    private func isEditingText(_ item: ClipboardItem) -> Bool {
        library.isEditingText(of: item.id)
    }

    private var draftBinding: Binding<String> {
        Binding(get: { library.textEdit?.draft ?? "" }, set: { library.textEdit?.draft = $0 })
    }

    private func revealed(_ id: UUID, isShown: Bool, container: ModelContainer) async -> String? {
        guard isShown else { return nil }
        return await HiddenClipReveal.readableText(from: ClipContent.payload(itemID: id, container: container))
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

    @ViewBuilder
    private func share(_ item: ClipboardItem, concealment: CardConcealment) -> some View {
        if concealment.isConcealed {
            EmptyView()
        } else if item.type == .image, let container = appState.historyContainer {
            ShareLink(
                item: DeferredPictureTransfer(
                    itemID: item.id, container: container, isGIF: item.mimeType?.contains("gif") == true
                ),
                preview: SharePreview(item.type.presentation.label)
            )
        } else if let content {
            ShareLink(item: ClipTransfer(content: content), preview: SharePreview(item.type.presentation.label))
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
            share(item, concealment: concealment)
            Menu("More", systemImage: "ellipsis") {
                Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                    let id = item.id
                    Task { await appState.togglePin(id) }
                }
                CopyActionsMenu(item: item)
                AIActionsMenu(item: item)
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
