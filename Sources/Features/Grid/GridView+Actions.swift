// SPDX-License-Identifier: MIT
import AppKit
import OSLog
import PestoCore
import SwiftData
import SwiftUI

extension GridView {
    // MARK: - Keyboard handlers

    func handleEscape() {
        if appState.shelfAuthentication != nil {
            appState.finishShelfAuthentication(success: false)
            return
        }
        quickLookController.reconcileWithPanel()
        if quickLookController.isOpen {
            quickLookController.close()
            return
        }
        if HoverCardHost.shared.closeForEscape() { return }
        if isPinnedHost {
            // Floating window: Escape clears selection; search dismissal is handled by onEscapeFromSearch.
            selection.clear()
            return
        }
        if selection.isEmpty {
            appState.close()
        } else {
            selection.clear()
        }
    }

    func handleReturn() {
        if copyOnly {
            guard focusedIndex < displayedItems.count else { return }
            appState.writeItem(displayedItems[focusedIndex])
            return
        }
        if selection.count > 1 {
            pasteSelectedOneByOne()
        } else {
            guard focusedIndex < cachedFilteredItems.count else { return }
            selectItem(cachedFilteredItems[focusedIndex])
        }
    }

    func scrollToFocused() {
        guard displayedItems.indices.contains(focusedIndex) else { return }
        scrollRequest = ShelfScrollRequest(id: displayedItems[focusedIndex].id, animated: true)
    }

    /// UI-test only: a screen's worth of cards at a time, so each is drawn once on the way (a jump to the end draws
    /// only the last few). Writes `walk-done` when the last clip is reached.
    func walkShelfToEnd() {
        Task { @MainActor in
            var index = 0
            while index < displayedItems.count - 1 {
                index = min(index + 6, displayedItems.count - 1)
                focusedIndex = index
                scrollToFocused()
                try? await Task.sleep(for: .milliseconds(60))
            }
            try? await Task.sleep(for: .milliseconds(500))
            let marker = AppPaths.supportDirectory.appendingPathComponent("walk-done")
            try? Data("\(displayedItems.count)".utf8).write(to: marker)
        }
    }

    /// To the edge, not to the first clip's id: a clip copied while the shelf was closed arrives in the same update
    /// that opens it, and the id of the clip that *was* first left the new one off screen.
    func scrollToStart() {
        scrollPosition.scrollTo(edge: .leading)
    }

    var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }

    /// The row slides in from the side the new collection's chip is on and the old row fades away.
    var collectionSwitchTransition: AnyTransition {
        let order: [UUID?] = [nil] + pinboards.map { Optional($0.id) }
        let direction = ShelfMotion.switchDirection(
            order: order, from: previousCollectionID, to: appState.selectedCollectionID
        )
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(x: (layoutDirection == .rightToLeft ? -direction : direction) * ShelfMotion
                        .collectionSlide)),
            removal: .opacity
        )
    }

    func pasteNth(_ number: Int) {
        let index = number - 1
        guard displayedItems.indices.contains(index) else { return }
        focusedIndex = index
        scrollToFocused()
        if copyOnly {
            appState.writeItem(displayedItems[index])
        } else {
            selectItem(displayedItems[index])
        }
    }

    /// Return in the search field pastes the focused result, so a search can be finished without the mouse.
    func handleReturnFromSearch() {
        let hasQuery = !appState.searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let hasFilters = !appState.searchTypeFilter.isEmpty || appState.searchDateFilter != .all
            || appState.searchSensitiveOnly || appState.searchRemoteOnly
        // A sentence that finds nothing is a request, not a term: Return asks (⌘Return asks whatever it finds).
        if AskHeuristic.returnAsks(text: appState.searchText, resultCount: cachedFilteredItems.count) {
            Task { await appState.askPesto() }
            return
        }
        guard hasQuery || hasFilters, !cachedFilteredItems.isEmpty else { return }
        let index = min(max(focusedIndex, 0), cachedFilteredItems.count - 1)
        selectItem(cachedFilteredItems[index])
    }

    /// ⇧Return in the search field: the focused result, as plain text.
    func pastePlainFromSearch() {
        guard !copyOnly, !cachedFilteredItems.isEmpty else { return }
        let index = min(max(focusedIndex, 0), cachedFilteredItems.count - 1)
        let item = cachedFilteredItems[index]
        guard ShelfKeyGate.plainPasteAllowed(for: item.type) else { return }
        selectItemWithTransform(item, transform: .stripFormatting)
    }

    func selectAllShown() {
        guard !copyOnly else { return }
        selection.selectAll(cachedFilteredIDs)
    }

    func handleSpace() {
        guard !copyOnly else { return }
        guard focusedIndex < cachedFilteredItems.count else { return }
        selection.toggle(cachedFilteredItems[focusedIndex].id)
    }

    /// The whole text of an ordinary clip, so a long document is summarized and not its first 500 characters. A secret
    /// stays masked (the model never sees it), and a clip too big to decrypt on the main thread falls back to its
    /// preview, which the answer then says.
    private func aiSource(for item: ClipboardItem) -> (text: String, totalCharacters: Int?) {
        guard item.sensitivityRaw == nil, DetailPopoverContent.canRead(byteSize: item.byteSize) else {
            return (item.gridPreview, item.textLength)
        }
        return (ClipText.full(of: item), nil)
    }

    func runAIAction(_ action: AIAction, on item: ClipboardItem) {
        guard action == .describeImage else {
            let source = aiSource(for: item)
            appState.runAIAction(
                action, text: source.text, totalCharacters: source.totalCharacters,
                isProtected: item.sensitivityRaw != nil, sourceItemID: item.id,
                fullLength: item.textLength > 0 ? item.textLength : nil
            )
            return
        }
        let (container, id) = (modelContext.container, item.id)
        Task {
            let service = ThumbnailService(modelContainer: container)
            guard let image = await service.thumbnail(for: id, maxPixel: 1024) else {
                appState.aiResult = AIResult(
                    action: action, sourcePreview: "Image", result: "That picture couldn\u{2019}t be read.",
                    isError: true
                )
                return
            }
            appState.runImageDescription(image.data)
        }
    }

    func handleClick(_ click: ShelfClick, item: ClipboardItem) {
        let extendsSelection = !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift])
        switch ShelfTap.route(
            copyOnly: copyOnly, pastesOnClick: pasteImmediately, hasSelection: !selection.isEmpty,
            extendsSelection: extendsSelection, click: click
        ) {
        case .copy:
            copyToPasteboard(item)
            flash(item.id)
        case .toggleSelection: selection.toggle(item.id)
        case .focus:
            if let index = displayedItems.firstIndex(where: { $0.id == item.id }) { focusedIndex = index }
        case .paste:
            selectItem(item)
            flash(item.id)
        case .ignore: break
        }
    }

    /// Only the floating window stays open after a click, so only there does the card answer with a wash.
    private func flash(_ id: UUID) {
        guard isPinnedHost else { return }
        flashedID = id
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if flashedID == id { flashedID = nil }
        }
    }

    // MARK: - Single-item paste (existing flow)

    static let pasteLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "paste")

    func selectItem(_ item: ClipboardItem) {
        let route = ShelfPaste.route(
            isLocked: appState.isHistoryLockedNow(), isPasting: isPasting, pinnedWindow: pasteImmediately
        )
        guard route != .ignore else {
            if !appState.isHistoryLockedNow() {
                Self.pasteLogger.warning("[paste] selectItem blocked — isPasting guard active")
            }
            return
        }
        isPasting = true
        Self.pasteLogger.log("[paste] selectItem called pasteImmediately=\(pasteImmediately, privacy: .public)")
        if route == .inPlace {
            // Pinned-window flow: keep the panel visible, route through executePasteItem
            // which captures focus and runs the paste task without touching isOverlayVisible.
            appState.notePasted(item, in: modelContext)
            appState.shelfPasteTally[item.id, default: 0] += 1
            appState.pasteInPlace?(item)
            // Release the guard after the focus-capture / write window has elapsed so
            // the user can pick a second card quickly. 500 ms matches FocusRestoration
            // already-frontmost sleep + a small safety margin.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                isPasting = false
            }
            return
        }
        guard let payloadKind = shelfActions.writeItem(item) else {
            isPasting = false
            return
        }
        appState.notePastedInBackground(item, in: modelContext)
        Self.pasteLogger.log("[paste] closing the shelf to paste")
        appState.close(.paste(item, payloadKind))
    }

    func selectItemWithTransform(_ item: ClipboardItem, transform: TextTransform) {
        guard !appState.isHistoryLockedNow() else { return }
        let rawText = extractText(from: item)
        let transformed = transform.apply(to: rawText, language: item.detectedLanguage)
        shelfActions.writeText(transformed, item.sensitivityRaw != nil)
        appState.notePastedInBackground(item, in: modelContext)
        appState.close(.paste(item, .text(transformed)))
    }

    func copyItemWithTransform(_ item: ClipboardItem, transform: TextTransform) {
        guard !appState.isHistoryLockedNow() else { return }
        let rawText = extractText(from: item)
        let transformed = transform.apply(to: rawText, language: item.detectedLanguage)
        shelfActions.writeText(transformed, item.sensitivityRaw != nil)
        appState.noteCopied(item, in: modelContext)
    }

    /// Copies the clip as it is and moves it to the front, unless nothing was written (locked, or a blob that will not
    /// open).
    func copyFocused() {
        if canPasteAll, selectedItems.count > 1, !appState.isHistoryLockedNow() {
            copySelectedJoined()
            return
        }
        guard displayedItems.indices.contains(focusedIndex) else { return }
        copyToPasteboard(displayedItems[focusedIndex])
        Announcer.announce("Copied")
    }

    /// ⌘C with several clips selected copies them the way Paste All pastes them: joined by a blank line.
    private func copySelectedJoined() {
        guard let joined = ClipJoin.join(selectedItems) else { return }
        appState.writeText(joined.text, protected: joined.isProtected)
        if joined.leftOut > 0 {
            appState.showUserMessage("Copy takes up to 10 MB of text. The first clips you selected were copied.")
        }
        Announcer.announce("Copied")
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        guard appState.writeItem(item) != nil else { return }
        appState.noteCopied(item, in: modelContext)
    }

    func extractText(from item: ClipboardItem) -> String {
        ClipText.full(of: item)
    }

    // MARK: - Semantic search

    @MainActor
    func updateSemanticResults() async {
        let query = appState.searchText.trimmingCharacters(in: .whitespaces)
        guard query.count > 8, !query.hasPrefix("@") else {
            semanticSupplement = []
            return
        }
        // Waits out fast typing: this task restarts on every keystroke and an earlier one is cancelled here.
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        guard let queryEmbedding = await SemanticIndexer.shared.embed(text: query), !Task.isCancelled else {
            if !Task.isCancelled { semanticSupplement = [] }
            return
        }
        let threshold: Float = 0.7
        let snapshot = items
        let ranked: [ClipboardItem] = snapshot
            .compactMap { item -> (ClipboardItem, Float)? in
                guard let data = item.embeddingData else { return nil }
                let sim = SemanticIndexer.cosineSimilarity(queryEmbedding, data)
                return sim >= threshold ? (item, sim) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        semanticSupplement = ranked
    }

    // MARK: - Paste All

    func pasteAllSelected() {
        guard canPasteAll, !appState.isHistoryLockedNow() else { return }
        guard !isPasting else { return }
        isPasting = true
        let chosen = selectedItems
        guard let representative = chosen.first, let joined = ClipJoin.join(chosen) else {
            isPasting = false
            return
        }
        if joined.leftOut > 0 {
            appState.showUserMessage(
                "Paste All takes up to 10 MB of text. The first clips you selected were pasted."
            )
        }
        appState.writeText(joined.text, protected: joined.isProtected)
        // Use the first selected item as the representative — its expiresAt is checked
        // by handleOverlayHidden, and since these clips typically have no TTL it no-ops.
        selection.clear()
        appState.close(.paste(representative, .text(joined.text)))
    }

    func assignShortcut(_ slot: Int?, toClip id: UUID) {
        Task {
            await appState.attempt("Couldn’t save the shortcut") {
                _ = try await appState.storageService?.assignHotkeySlot(slot, to: id)
            }
        }
    }

    func togglePin(ofClip id: UUID) {
        Task {
            await appState.attempt("Couldn’t pin the clip") {
                _ = try await appState.storageService?.togglePinned(id: id)
            }
        }
    }

    /// ⌘Return: Show or Hide the focused clip when it is covered.
    func showFocusedHidden() {
        guard displayedItems.indices.contains(focusedIndex) else { return }
        showRequest = ShowRequest(itemID: displayedItems[focusedIndex].id)
    }

    // MARK: - Save Image and Copy As

    /// ⌘S on the focused clip. Returns false when there is nothing to save, so the key reaches the search field or
    /// the app underneath untouched.
    /// ⌘Y: Quick Look on the focused clip; nothing opens for a clip that is covered.
    func quickLookFocused() {
        guard displayedItems.indices.contains(focusedIndex) else { return }
        let item = displayedItems[focusedIndex]
        guard ShelfKeyGate.quickLookAllowed(
            isHidden: item.sensitivityRaw != nil,
            isFilteredContent: item.isNSFW,
            isPendingAnalysis: item.analysisPending,
            isCoveredForSharing: isPrivacyBlurred
        ) else { return }
        quickLookController.toggle(item: item)
    }

    /// ⇧Return: the focused clip's text, pasted without formatting.
    func pastePlainFocused() {
        guard !copyOnly, displayedItems.indices.contains(focusedIndex) else { return }
        let item = displayedItems[focusedIndex]
        guard ShelfKeyGate.plainPasteAllowed(for: item.type) else { return }
        selectItemWithTransform(item, transform: .stripFormatting)
    }

    func saveFocusedImage() -> Bool {
        guard displayedItems.indices.contains(focusedIndex) else { return false }
        let item = displayedItems[focusedIndex]
        guard ImageExport.keyboardSaveAllowed(
            isImage: item.type == .image,
            isFilteredContent: item.isNSFW,
            isHidden: item.sensitivity != nil,
            isPendingAnalysis: item.analysisPending,
            isCoveredForSharing: isPrivacyBlurred
        ) else { return false }
        saveImage(item)
        return true
    }

    func saveImage(_ item: ClipboardItem) {
        guard let blob = item.blob, let data = blob.decryptedData() else {
            Announcer.announce("Couldn’t save the picture")
            return
        }
        let chosen = ImageExport.saveFolder(
            chosenPath: AppDefaults.store.value(for: Setting.pictureSaveFolder), downloads: AppPaths.downloadsDirectory
        ) { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
                && FileManager.default.isWritableFile(atPath: url.path)
        }
        let folder = chosen.folder
        let url = ImageExport.destination(
            in: folder,
            base: ImageExport.baseName(title: item.customTitle, date: .now),
            fileExtension: ImageExport.fileExtension(forUTI: blob.mimeType)
        ) { FileManager.default.fileExists(atPath: $0.path) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .withoutOverwriting)
            Announcer.announce(
                chosen.usedFallback
                    ? "Saved \(url.lastPathComponent) to Downloads, because the chosen folder is not available"
                    : "Saved \(url.lastPathComponent) to \(folder.lastPathComponent)"
            )
            flashSaved(item.id)
        } catch {
            Self.pasteLogger.error("Save Image failed: \(error.localizedDescription, privacy: .public)")
            Announcer.announce("Couldn’t save the picture")
        }
    }

    func copyText(_ item: ClipboardItem, _ text: String) {
        appState.writeText(text, protected: item.sensitivityRaw != nil)
        appState.noteCopied(item, in: modelContext)
        if item.sensitivityRaw != nil {
            Announcer.announce("Copied")
        } else {
            Announcer.announce("Copied \(text)")
        }
    }

    func copyImageData(_ data: Data, from item: ClipboardItem) {
        guard let image = NSImage(data: data) else { return }
        copyImage(image, from: item)
    }

    func copyImage(_ image: NSImage, from item: ClipboardItem) {
        appState.writeImage(image, protected: item.sensitivityRaw != nil)
        appState.noteCopied(item, in: modelContext)
        Announcer.announce("Copied image")
    }

    private func flashSaved(_ id: UUID) {
        flashedID = id
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if flashedID == id { flashedID = nil }
        }
    }

    // MARK: - Delete

    /// The Delete key: the selection, or the focused clip.
    func requestDeleteForKey() {
        let focused = displayedItems.indices.contains(focusedIndex) ? displayedItems[focusedIndex].id : nil
        let targets = ShelfDeletion.targets(
            selection: selection.ordered(in: cachedFilteredIDs), focused: focused
        )
        if !targets.isEmpty { pendingDelete = targets }
    }

    /// A card's own Delete: the selection when the card is part of one, otherwise that card.
    func requestDelete(ofCard id: UUID) {
        pendingDelete = ShelfDeletion.targets(
            selection: selection.ordered(in: cachedFilteredIDs), requestedFor: id
        )
    }

    /// Whether ⌘Z will bring these clips back: not a large or expiring one, and not more than `UndoPolicy` holds.
    func deletionCanBeUndone(_ ids: [UUID]) -> Bool {
        let wanted = Set(ids)
        return UndoPolicy.canHold(cachedFilteredItems.filter { wanted.contains($0.id) })
    }

    func confirmDelete() {
        guard let ids = pendingDelete else { return }
        pendingDelete = nil
        deleteSelected(ids)
    }

    func deleteSelected(_ ids: [UUID]) {
        guard !appState.isHistoryLockedNow() else { return }
        let mark = appState.undoHistory?.recordedCount ?? 0
        Task {
            await appState.attempt("Couldn’t delete the selected clips") {
                if let count = try await appState.storageService?.deleteItems(ids: ids, reason: .user) {
                    AutoBackupSettings().lowerBaseline(by: count)
                    appState.offerUndo(since: mark)
                }
            }
        }
        selection.clear()
    }

    // MARK: - Paste One by One

    func pasteSelectedOneByOne() {
        let (chosen, leftOut) = PasteStack.limited(selectedItems, byteSize: \.byteSize)
        if leftOut > 0 {
            appState.showUserMessage(
                "Paste One by One takes \(CountText.clips(PasteStack.maxItems)) or 50 MB. The first ones are in it."
            )
        }
        let stackItems = chosen.map { PasteStack.Item(clip: $0) }

        guard stackItems.count > 1 else { return }

        let sources = chosen.map {
            StackSnippetSource(id: $0.id, isSnippet: $0.isTemplate, remembered: $0.metadata.fieldMemory ?? [:])
        }
        Task {
            guard let ready = await appState.expandedStackItems(stackItems, sources: sources) else { return }
            let stack = PasteStack(items: ready)
            selection.clear()

            // Activate the stack — AppDelegate's overlay-hidden handler will paste item 1.
            appState.activeStack = stack
            appState.close(.startStack)
        }
    }
}
