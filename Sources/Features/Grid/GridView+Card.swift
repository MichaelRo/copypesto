// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension GridView {
    /// One card. What it can ask the shelf to do arrives through `cardActions` in the environment, built once for the
    /// whole row; only the values that differ per card are parameters.
    @ViewBuilder
    func cardView(
        for item: ClipboardItem,
        at idx: Int,
        collections: [CollectionRef],
        showsFirstCopyTime: Bool,
        isBlurred: Bool
    )
    -> some View {
        if detail.isLight {
            LightCard(item: item, isFocused: idx == focusedIndex)
        } else {
            fullCard(
                for: item, at: idx, collections: collections, showsFirstCopyTime: showsFirstCopyTime,
                isBlurred: isBlurred
            )
        }
    }

    private func fullCard(
        for item: ClipboardItem,
        at idx: Int,
        collections: [CollectionRef],
        showsFirstCopyTime: Bool,
        isBlurred: Bool
    )
    -> some View {
        let isSuggested = appState.shelfSuggestion?.targetClipID == item.id
            && !isBlurred
            && !appState.isHistoryLocked
        let suggestedHotkeySlot = isSuggested ? appState.shelfSuggestion?.targetSlot : nil
        return ClipboardCard(
            item: item,
            isFocused: idx == focusedIndex,
            focusAnchor: focusAnchor,
            shortcutNumber: idx < 9 ? idx + 1 : nil,
            revealsDetail: DetailPopoverPolicy.keyboardReveals(itemID: item.id, revealedID: keyboardRevealedID),
            detailSuppressed: detailSuppressed,
            scrollState: scrollState,
            isSelected: selection.contains(item.id),
            showRequest: showRequest,
            isFlashing: flashedID == item.id,
            unavailableHotkeySlots: appState.hotkeyController.unavailableSlots,
            isPrivacyBlurred: isBlurred,
            availableCollections: collections,
            revealedFromOutside: revealedIDs.contains(item.id),
            previewsAllowed: !appState.isHistoryLocked,
            hideSecretsGeneration: hideSecretsGeneration,
            canRevealHidden: appState.authenticationAvailability == .available,
            isSuggested: isSuggested,
            suggestedHotkeySlot: suggestedHotkeySlot,
            showsFirstCopyTime: showsFirstCopyTime,
            inCollection: appState.selectedCollectionID != nil
        )
        .equatable()
        .overlay(alignment: cardInsertionBar?.target == item.id && cardInsertionBar?
            .side == .before ? .leading : .trailing)
        {
            if let bar = cardInsertionBar, bar.target == item.id {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent)
                    .frame(width: 2)
                    .padding(.vertical, 8)
                    .offset(x: bar.side == .before ? -5 : 5)
            }
        }
        .onDrop(
                of: [
                    UTType.utf8PlainText.identifier, UTType.plainText.identifier,
                    UTType.png.identifier, UTType.tiff.identifier, UTType.fileURL.identifier
                ],
                delegate: CardReorderDropDelegate(
                    appState: appState,
                    targetID: item.id,
                    cardWidth: cardDimensions.width,
                    canReorder: showsFirstCopyTime,
                    insertionBar: $cardInsertionBar,
                    onReorder: { sourceID, side in
                        reorderItem(from: sourceID, relativeTo: item.id, side: side)
                    }
                )
            )
    }

    /// What every card on this shelf can do. Built once per update of the grid, not once per card.
    var cardActions: CardActions {
        let editor = clipEditor
        var actions = CardActions(
            detailDismissed: { keyboardRevealedID = nil },
            pointerEntered: { keyboardRevealedID = nil },
            click: { handleClick($1, item: $0) },
            paste: { selectItem($0) },
            aiAction: { runAIAction($1, on: $0) },
            toggleSensitive: { item in editor.edit(item) { $0.isNSFW.toggle() } },
            setExpiry: { item, date in
                editor.edit(item, refreshesRow: false, changesFilter: false) { $0.expiresAt = date }
            },
            quickLook: { item in
                if item.sensitivityRaw == nil {
                    quickLookController.toggle(item: item)
                    return
                }
                Task {
                    let permitted = await appState
                        .authenticateInShelf(reason: "Show a clip that is hidden on the shelf")
                    if permitted { quickLookController.toggle(item: item) }
                }
            },
            authenticate: { reason in await appState.authenticateInShelf(reason: reason) },
            decodeJWT: { item in
                guard await appState.authenticateInShelf(reason: "Decode a token that is hidden on the shelf") else {
                    return nil
                }
                guard let decoding = JWTDecoder.decode(ClipText.full(of: item)) else { return .unreadable }
                return .decoded(decoding)
            },
            decodePopoverKeys: { appState.decodePopoverKeys = $0 },
            copyProtectedText: { appState.writeText($0, protected: true) },
            pasteAs: { selectItemWithTransform($0, transform: $1) },
            copyTransformed: { copyItemWithTransform($0, transform: $1) },
            structuredTransforms: { item in
                appState.isHistoryLockedNow() ? [] : StructuredPaste.offered(for: item)
            },
            entityAction: { entity in
                EntityActionRunner.run(entity)
                appState.close()
            },
            dragStarted: { item in
                appState.isDragging = true
                appState.draggingItemID = item.id
                Task { @MainActor in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        switch DragStateFallback.decide(
                            stillThisDrag: appState.draggingItemID == item.id,
                            buttonDown: NSEvent.pressedMouseButtons & 1 == 1
                        ) {
                        case .checkAgain:
                            continue
                        case .clear:
                            appState.draggingItemID = nil
                            appState.isDragging = false
                            return
                        case .stop:
                            return
                        }
                    }
                }
            },
            assignHotkey: { assignShortcut($1, toClip: $0.id) },
            togglePin: { togglePin(ofClip: $0.id) },
            editText: { appState.openTextEditor?($0, true) },
            copy: { copyToPasteboard($0) },
            recognizedTextOffered: { !appState.isHistoryLockedNow() && RecognizedText.isOffered(for: $0) },
            copyRecognizedText: { copyRecognizedText($0) },
            copyText: copyText,
            copyImageData: { copyImageData($1, from: $0) },
            copyImage: { copyImage($1, from: $0) },
            saveImage: { saveImage($0) },
            moveToCollection: { item, targetID in editor.edit(item) { $0.collectionID = targetID } },
            delete: { requestDelete(ofCard: $0.id) },
            revealChanged: { item, shown in
                if shown { revealedIDs.insert(item.id) } else { revealedIDs.remove(item.id) }
            }
        )
        actions.copyAsFile = { copyAsFile($0) }
        actions.showDetails = { showDetails(of: $0) }
        if copyOnly {
            actions.paste = nil
        } else {
            actions.pasteAsFile = { pasteAsFile($0) }
        }
        return actions
    }

    /// Every edit to a clip goes through one editor, so none of them skips the rollback, the message or the row
    /// refresh.
    var clipEditor: ClipEditor {
        ClipEditor(
            context: modelContext,
            historyStore: appState.historyStore,
            report: { appState.attempt($0, $1) },
            didEdit: { filterEditGeneration += 1 },
            undoHistory: appState.undoHistory
        )
    }

    var isStaticCollectionSelected: Bool {
        guard let pid = appState.selectedCollectionID else { return false }
        return pinboards.first { $0.id == pid }?.isSmart == false
    }

    var cardRow: some View {
        let actions = cardActions
        let editor = clipEditor
        let collections = pinboards.map { CollectionRef(id: $0.id, name: $0.name, symbolName: $0.symbolName) }
        let showsFirstCopy = isStaticCollectionSelected
        let blurred = isPrivacyBlurred
        return LazyHStack(spacing: 8) {
            ForEach(displayedItems.indices, id: \.self) { idx in
                let item = displayedItems[idx]
                cardView(
                    for: item,
                    at: idx,
                    collections: collections,
                    showsFirstCopyTime: showsFirstCopy,
                    isBlurred: blurred
                )
                // A new text is a new card: the main context's merge alone does not redraw it (ADR 0050).
                .id(item.contentHash)
                    .id(item.id)
                    .transition(cardTransition)
            }
            if cachedFilteredItems.count > displayedItems.count {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
                    .onAppear {
                        guard cachedFilteredItems.count > displayLimit else { return }
                        displayLimit += 500
                        displayedItems = Array(cachedFilteredItems.prefix(displayLimit))
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard cards")
        .environment(\.cardActions, actions)
        .environment(\.clipEditor, editor)
    }

    func reorderItem(from sourceID: UUID, relativeTo targetID: UUID, side: CollectionReorder.Side) {
        guard appState.historyStore != nil else { return }
        let ids = cachedFilteredItems.map(\.id)
        let reorderedIDs = CollectionReorder.order(ids, moving: sourceID, relativeTo: targetID, side: side)
        guard reorderedIDs != ids else { return }
        let byID = Dictionary(cachedFilteredItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentItems = reorderedIDs.compactMap { byID[$0] }
        let order = Dictionary(reorderedIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        clipEditor.edit(currentItems) { $0.collectionOrder = order[$0.id] }
    }

    private func copyAsFile(_ item: ClipboardItem) {
        guard appState.writeAsFile(item) != nil else { return }
        appState.noteCopied(item, in: modelContext)
        Announcer.announce("Copied as file")
    }

    private func pasteAsFile(_ item: ClipboardItem) {
        guard !appState.isHistoryLockedNow(), let payloadKind = appState.writeAsFile(item) else { return }
        appState.notePastedInBackground(item, in: modelContext)
        appState.close(.paste(item, payloadKind))
    }
}

private struct CardReorderDropDelegate: DropDelegate {
    let appState: AppState
    let targetID: UUID
    let cardWidth: CGFloat
    let canReorder: Bool
    @Binding var insertionBar: CollectionReorder.InsertionBar?
    let onReorder: (UUID, CollectionReorder.Side) -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        canReorder && appState.draggingItemID != nil && appState.draggingItemID != targetID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canReorder, let sourceID = appState.draggingItemID, sourceID != targetID else { return nil }
        let side = CollectionReorder.Side.at(x: info.location.x, width: cardWidth)
        let next = CollectionReorder.InsertionBar(target: targetID, side: side)
        if insertionBar != next { insertionBar = next }
        return DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        if insertionBar?.target == targetID { insertionBar = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            insertionBar = nil
            appState.draggingItemID = nil
            appState.isDragging = false
        }
        guard canReorder, let sourceID = appState.draggingItemID, sourceID != targetID else { return false }
        let side = CollectionReorder.Side.at(x: info.location.x, width: cardWidth)
        onReorder(sourceID, side)
        return true
    }
}
