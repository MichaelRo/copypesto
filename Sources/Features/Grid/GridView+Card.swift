// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension GridView {
    /// One card. What it can ask the shelf to do arrives through `cardActions` in the environment, built once for the
    /// whole row; only the values that differ per card are parameters.
    func cardView(for item: ClipboardItem, at idx: Int) -> some View {
        let isSuggested = appState.shelfSuggestion?.targetClipID == item.id
            && !appState
            .isContentCovered(screenSharingPrivacy: AppDefaults.store.value(for: Setting.screenSharingPrivacy))
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
            isPrivacyBlurred: isPrivacyBlurred,
            availableCollections: pinboards.map { CollectionRef(
                id: $0.id,
                name: $0.name,
                symbolName: $0.symbolName
            ) },
            revealedFromOutside: revealedIDs.contains(item.id),
            previewsAllowed: !appState.isHistoryLocked,
            hideSecretsGeneration: hideSecretsGeneration,
            canRevealHidden: appState.authenticationAvailability == .available,
            isSuggested: isSuggested,
            suggestedHotkeySlot: suggestedHotkeySlot
        )
        .environment(\.clipEditor, clipEditor)
        .onDrop(
            of: [
                UTType.utf8PlainText.identifier, UTType.plainText.identifier,
                UTType.png.identifier, UTType.tiff.identifier, UTType.fileURL.identifier
            ],
            isTargeted: nil
        ) { _ in
            guard isStaticCollectionSelected,
                  let draggedID = appState.draggingItemID,
                  draggedID != item.id else { return false }
            reorderItem(from: draggedID, to: item.id)
            appState.draggingItemID = nil
            appState.isDragging = false
            return true
        }
    }

    /// What every card on this shelf can do. Built once per update of the grid, not once per card.
    var cardActions: CardActions {
        let editor = clipEditor
        return CardActions(
            detailDismissed: { keyboardRevealedID = nil },
            pointerEntered: { keyboardRevealedID = nil },
            click: { handleClick($1, item: $0) },
            aiAction: { runAIAction($1, on: $0) },
            toggleSensitive: { item in editor.edit(item) { $0.isNSFW.toggle() } },
            setExpiry: { item, date in
                editor.edit(item, refreshesRow: false, changesFilter: false) { $0.expiresAt = date }
            },
            quickLook: { item in
                Task {
                    let permitted = item.sensitivityRaw == nil
                        ? true
                        : await appState.authenticateInShelf(reason: "Show a clip that is hidden on the shelf")
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
            entityAction: { entity in
                EntityActionRunner.run(entity)
                appState.close()
            },
            dragStarted: { item in
                appState.isDragging = true
                appState.draggingItemID = item.id
                // Safety fallback: if the drag ends without a chip accepting the drop
                // (cancelled inside the panel), clear the ID after 3s so the next drag
                // doesn't accidentally move the wrong item.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    if appState.draggingItemID == item.id {
                        appState.draggingItemID = nil
                        appState.isDragging = false
                    }
                }
            },
            assignHotkey: { assignShortcut($1, toClip: $0.id) },
            togglePin: { togglePin(ofClip: $0.id) },
            copy: { copyToPasteboard($0) },
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

    func reorderItem(from sourceID: UUID, to targetID: UUID) {
        guard appState.historyStore != nil else { return }
        var currentItems = cachedFilteredItems
        guard let fromIndex = currentItems.firstIndex(where: { $0.id == sourceID }),
              let toIndex = currentItems.firstIndex(where: { $0.id == targetID }) else { return }
        let moved = currentItems.remove(at: fromIndex)
        currentItems.insert(moved, at: toIndex)
        let order = Dictionary(currentItems.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        clipEditor.edit(currentItems) { $0.collectionOrder = order[$0.id] }
    }
}
