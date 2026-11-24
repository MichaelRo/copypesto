// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore
import SwiftUI

/// What the one library page is showing and what it has open, kept above the compact and regular layouts so a change
/// of width (Split View, rotation) keeps the scope, the search and the open clip.
@MainActor
@Observable
final class LibraryModel {
    var filter = LibraryFilter()
    var query = ""
    var isSearching = false
    var openClipID: UUID?
    /// The text editor open in the detail, kept here so a change of layout (the phone's sheet, the pad's inspector)
    /// does not lose what was typed. Memory only, never scene storage: it holds a clip's plaintext.
    var textEdit: TextEditSession?
    /// The first card showing in the grid, restored when the grid is drawn again by the other layout.
    @ObservationIgnored var scrollAnchor: CardIdentity?
    #if DEBUG
    /// `UITestLayout`: the width class a UI test forces, nil for the real one.
    var forcedSizeClass: UserInterfaceSizeClass? = UITestLayout.initialSizeClass
    #endif

    var forcedSizeClassIfDebug: UserInterfaceSizeClass? {
        #if DEBUG
        forcedSizeClass
        #else
        nil
        #endif
    }

    enum SettingsDestination: Hashable {
        case keyboard
        case sync
        case insights
    }

    var columns: NavigationSplitViewVisibility = .all
    var showsSettings = false
    var settingsDestination: SettingsDestination?
    var showsQuickInsertSetup = false
    var isComposing = false
    var snippetEditor: SnippetEditorTarget?
    var pendingSnippetAfterComposing: SnippetEditorTarget?
    var picksSyncFolder = false
    var isNamingCollection = false
    var isImportingCollection = false
    var editingCollection: Pinboard?
    var pendingDelete: UUID?
    var sharing: ClipShare?
    var flashedClipID: UUID?
    var copyCount = 0
    var isSelecting = false
    var selectedClipIDs: Set<UUID> = []
    var isAsking = false
    private(set) var activeAskSentence: String?
    private(set) var askGeneration = 0
    @ObservationIgnored var visibleResultCount = 0
    @ObservationIgnored private var askTask: Task<Void, Never>?
    @ObservationIgnored private var cachedAppsRevision = -1
    @ObservationIgnored private var cachedAppsList: [SourceApp] = []
    /// Bumped when the grid should take the history's order again (`GridOrder`).
    private(set) var orderVersion = 0
    @ObservationIgnored let order = GridOrder()

    enum SnippetEditorTarget: Equatable, Identifiable {
        case new(initialText: String = "")
        case edit(id: UUID, title: String, text: String)

        var id: String {
            switch self {
            case .new: "new"
            case let .edit(id, _, _): id.uuidString
            }
        }
    }

    struct TextEditSession: Equatable {
        let clipID: UUID
        var draft: String
    }

    func open(_ id: UUID) {
        if textEdit?.clipID != id { textEdit = nil }
        openClipID = id
    }

    func beginTextEdit(of id: UUID, text: String) {
        textEdit = TextEditSession(clipID: id, draft: text)
    }

    func endTextEdit() {
        textEdit = nil
    }

    func isEditingText(of id: UUID) -> Bool {
        textEdit?.clipID == id
    }

    func beginNewSnippet(initialText: String = "") {
        snippetEditor = .new(initialText: initialText)
    }

    func switchFromComposeToSnippet(initialText: String = "") {
        pendingSnippetAfterComposing = .new(initialText: initialText)
        isComposing = false
    }

    func presentPendingSnippetIfNeeded() {
        guard let pending = pendingSnippetAfterComposing else { return }
        pendingSnippetAfterComposing = nil
        snippetEditor = pending
    }

    func beginSnippetEdit(of item: ClipboardItem, text: String) {
        snippetEditor = .edit(id: item.id, title: item.customTitle ?? "", text: text)
    }

    func beginSelection(with initialID: UUID? = nil) {
        isSelecting = true
        if let initialID { selectedClipIDs.insert(initialID) }
    }

    func toggleSelection(_ id: UUID) {
        if selectedClipIDs.contains(id) {
            selectedClipIDs.remove(id)
        } else {
            selectedClipIDs.insert(id)
        }
    }

    func selectAll(_ ids: [UUID]) {
        isSelecting = true
        selectedClipIDs = Set(ids)
    }

    func applyDragSelection(
        from anchorID: UUID,
        to currentID: UUID,
        in visibleIDs: [UUID],
        baseSelection: Set<UUID>,
        selecting: Bool
    ) {
        guard let start = visibleIDs.firstIndex(of: anchorID),
              let end = visibleIDs.firstIndex(of: currentID) else { return }
        applyDragSelection(
            fromIndex: start,
            toIndex: end,
            in: visibleIDs,
            baseSelection: baseSelection,
            selecting: selecting
        )
    }

    func applyDragSelection(
        fromIndex start: Int,
        toIndex end: Int,
        in visibleIDs: [UUID],
        baseSelection: Set<UUID>,
        selecting: Bool
    ) {
        guard visibleIDs.indices.contains(start), visibleIDs.indices.contains(end) else { return }
        let range = min(start, end)...max(start, end)
        var updated = baseSelection
        for index in range {
            if selecting {
                updated.insert(visibleIDs[index])
            } else {
                updated.remove(visibleIDs[index])
            }
        }
        if selectedClipIDs != updated {
            selectedClipIDs = updated
        }
    }

    func endSelection() {
        isSelecting = false
        selectedClipIDs = []
    }

    func targetCollectionID(in collections: [Pinboard]) -> UUID? {
        guard case let .collection(id) = filter.scope,
              let board = collections.first(where: { $0.id == id }),
              !board.isSmart else { return nil }
        return id
    }

    /// The history locked: nothing it had open, typed or was about to delete comes back with the unlock.
    func closeEverything() {
        query = ""
        isSearching = false
        filter.endSearch()
        openClipID = nil
        textEdit = nil
        snippetEditor = nil
        scrollAnchor = nil
        showsSettings = false
        isComposing = false
        pendingSnippetAfterComposing = nil
        picksSyncFolder = false
        isNamingCollection = false
        isImportingCollection = false
        editingCollection = nil
        pendingDelete = nil
        sharing = nil
        cancelAsk()
        endSelection()
    }

    func didCopy(_ id: UUID) {
        copyCount += 1
        flashedClipID = id
        let count = copyCount
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, copyCount == count else { return }
            flashedClipID = nil
        }
    }

    /// A clip from the widget: the library goes back to All, out of any search, and takes the history's order (a copy
    /// moved the clip to the front). A copied clip's card flashes; a clip opened from the widget opens in its detail.
    func show(_ id: UUID, opensDetail: Bool) {
        cancelAsk()
        filter = LibraryFilter()
        query = ""
        isSearching = false
        openClipID = nil
        resort()
        if opensDetail {
            open(id)
        } else {
            didCopy(id)
        }
    }

    func availableApps(in store: HistoryStore?) -> [SourceApp] {
        guard isSearching, let store else {
            if store == nil {
                cachedAppsRevision = -1
                cachedAppsList = []
            }
            return []
        }
        if store.revision != cachedAppsRevision {
            cachedAppsList = LibraryFilter.availableApps(in: store.items)
            cachedAppsRevision = store.revision
        }
        return cachedAppsList
    }

    func appName(for bundleID: String, in store: HistoryStore?) -> String? {
        if let hit = cachedAppsList.first(where: { $0.bundleID == bundleID }) {
            return hit.name
        }
        guard let items = store?.items else { return nil }
        return items.first { $0.sourceBundleID == bundleID && $0.knownSourceAppName != nil }?.knownSourceAppName
            ?? LibraryFilter.availableApps(in: items).first { $0.bundleID == bundleID }?.name
    }

    func openSearch(_ text: String) {
        cancelAsk()
        filter = LibraryFilter()
        query = text
        isSearching = true
        openClipID = nil
        endSelection()
        resort()
    }

    func resort() {
        order.resort()
        orderVersion += 1
    }

    func endSearch() {
        cancelAsk()
        filter.endSearch()
    }

    func startAsk(
        using runAsk: @escaping @MainActor (String) async -> AskPestoQuery,
        isLocked: @escaping @MainActor () -> Bool
    ) {
        let sentence = query
        guard !sentence.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        cancelAsk()
        askGeneration &+= 1
        let expectedGeneration = askGeneration
        activeAskSentence = sentence
        isAsking = true
        askTask = Task { @MainActor [weak self] in
            let answer = await runAsk(sentence)
            guard let self, !Task.isCancelled, askGeneration == expectedGeneration else { return }
            isAsking = false
            activeAskSentence = nil
            askTask = nil
            withAnimation(Motion.animation(.pestoQuick)) {
                _ = applyAnswer(answer, to: sentence, isLocked: isLocked())
            }
        }
    }

    func cancelAsk() {
        askTask?.cancel()
        askTask = nil
        askGeneration &+= 1
        activeAskSentence = nil
        isAsking = false
    }

    /// Ask Pesto's answer: its words go to the search field and its kinds and range to the filter.
    func apply(_ query: AskPestoQuery) {
        self.query = query.keywords
        isSearching = true
        filter.apply(query)
    }

    /// The answer to `sentence` arrives after the person may have typed on, ended the search or locked the history;
    /// it is applied only to the search it was asked about. Returns whether it was applied.
    @discardableResult
    func applyAnswer(_ query: AskPestoQuery, to sentence: String, isLocked: Bool) -> Bool {
        guard !isLocked, isSearching, self.query == sentence else { return false }
        apply(query)
        return true
    }
}
