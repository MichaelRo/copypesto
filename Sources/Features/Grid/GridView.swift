// SPDX-License-Identifier: MIT
import AppKit
import Combine
import PestoCore
import SwiftData
import SwiftUI

// Horizontal scroll grid of `ClipboardCard` views backed by a live SwiftData query.
// Cards share a single `.ultraThinMaterial` rail. Tapping a card writes its payload
// to NSPasteboard and triggers the 3-tier paste strategy.
//
// Multi-select: press Space to toggle selection of the focused card.
// When >1 cards are selected, an action bar offers Paste All (one block) and Paste One by One (a `PasteStack`).

struct GridView: View {
    /// When `true`, tapping or pressing Return copies the item to the clipboard instead of
    /// auto-pasting and closing the overlay. Used by the floating window when the user has
    /// opted out of auto-paste.
    var copyOnly: Bool = false
    /// When `true`, tapping or pressing Return triggers an immediate paste via the
    /// `executePasteItem` path (capture focus → write → CGEvent) without going through
    /// the overlay-hide state machine. Used by the floating window when auto-paste is on.
    /// Mutually exclusive with `copyOnly`; if both are set, `copyOnly` wins.
    var pasteImmediately: Bool = false
    var onFocusChanged: ((Color, CGFloat) -> Void)?

    /// The whole history, from the store the shelf and the floating window share (`HistoryStore`).
    var items: [ClipboardItem] {
        appState.historyStore?.items ?? []
    }

    @Query(sort: \Pinboard.sortOrder) var pinboards: [Pinboard]
    @Environment(AppState.self) var appState: AppState
    @Environment(\.shelfActions) var shelfActions: ShelfActionDispatcher
    @Environment(\.modelContext) var modelContext
    @State var focusedIndex = 0
    @State var focusAnchor = FocusedCardAnchor()
    @State var focusedID: UUID?
    @State var keyboardRevealedID: UUID?
    @State var pointerOrigin: CGPoint?
    @State var scrollState = ShelfScrollState()
    @State var scrollRequest: ShelfScrollRequest?
    @State var scrollPosition = ScrollPosition(edge: .leading)
    @State var showRequest: ShowRequest?
    @State var flashedID: UUID?
    @State var selection = GridSelection()
    @State var quickLookController = QuickLookPreviewController()
    @AppStorage(Setting.screenSharingPrivacy) var screenSharingPrivacy: Bool
    @AppStorage(Setting.cardSize) var cardSizeRaw: String
    @AppStorage(Setting.cardWidth) var cardWidth: Int
    @AppStorage(Setting.nsfwMode) var nsfwModeRaw: String
    @State var previousCollectionID: UUID?
    /// Number of filtered items currently shown. Extends by 500 when the user reaches the
    /// last visible card, giving infinite-scroll pagination.
    @State var displayLimit = 1000
    @State var semanticSupplement: [ClipboardItem] = []
    /// The clips waiting for the person to confirm deleting them (one, or the whole selection).
    @State var pendingDelete: [UUID]?
    /// Cached result of the filter pipeline. Recomputed via onChange(of: filterKey) so
    /// the O(n × passes) work runs only when filter inputs change, not on every body call
    /// (which fires on every hover, focus change, and @Published update in AppState).
    @State var cachedFilteredItems: [ClipboardItem] = []
    /// The ids of `cachedFilteredItems`, from the index, so no pass over the clips is needed to read them.
    @State var cachedFilteredIDs: [UUID] = []
    /// Bumped when a clip is edited in a way the filter reads (sensitive mark, collection, tags), which the other
    /// inputs of `FilterKey` do not show.
    @State var filterEditGeneration = 0

    // MARK: - Filter inputs key

    /// Cheap Hashable snapshot of every value the filter pipeline reads. Computing this in
    /// body is O(1); the expensive filter runs only when the key actually changes.
    private struct FilterKey: Hashable {
        let itemCount: Int
        /// Re-copying or pasting an older clip moves it to the front without changing the count.
        let newestItemID: UUID?
        let newestTimestamp: Date?
        let pinboardCount: Int
        let nsfwEnabled: Bool
        let isSearchActive: Bool
        let showHiddenNSFW: Bool
        let sensitiveOnly: Bool
        let remoteOnly: Bool
        let appChipFilter: Set<String>
        let bundleID: String?
        let collectionID: UUID?
        let searchText: String
        let searchTypeFilter: Set<String>
        let searchSourceFilter: Set<String>
        let searchDateFilter: AppState.SearchDateFilter
        let semanticCount: Int
        let editGeneration: Int
        /// A smart collection's rules can be edited without the number of collections changing.
        let collectionRules: Int
    }

    private var filterKey: FilterKey {
        FilterKey(
            itemCount: items.count,
            newestItemID: items.first?.id,
            newestTimestamp: items.first?.timestamp,
            pinboardCount: pinboards.count,
            nsfwEnabled: nsfwMode.hidesFromGrid,
            isSearchActive: appState.isSearchActive,
            showHiddenNSFW: appState.showHiddenNSFW,
            sensitiveOnly: appState.isSearchActive && appState.searchSensitiveOnly,
            remoteOnly: appState.isSearchActive && appState.searchRemoteOnly,
            appChipFilter: appState.appChipFilter,
            bundleID: appState.frontmostAppBundleID,
            collectionID: appState.selectedCollectionID,
            searchText: appState.searchText,
            searchTypeFilter: appState.searchTypeFilter,
            searchSourceFilter: appState.searchSourceFilter,
            searchDateFilter: appState.searchDateFilter,
            semanticCount: semanticSupplement.count,
            editGeneration: filterEditGeneration,
            collectionRules: pinboards.reduce(0) { $0 &+ ($1.smartPredicateData?.hashValue ?? 0) }
        )
    }

    private var cardDimensions: CGSize {
        CardSize.dimensions(sizeRaw: cardSizeRaw, customWidth: cardWidth)
    }

    /// Guards against rapid double-taps triggering two pastes on the same item.
    @State var isPasting = false
    @Environment(\.layoutDirection) var layoutDirection

    /// Hidden (blurred) clips the person has chosen to show. Cleared when the shelf closes.
    @State var revealedIDs: Set<UUID> = []
    /// Bumped when a secret the person chose to show must hide again (ADR 0003).
    @State var hideSecretsGeneration = 0

    var isPrivacyBlurred: Bool {
        appState.isContentCovered(screenSharingPrivacy: screenSharingPrivacy)
    }

    /// Visible subset of `cachedFilteredItems` — limited to `displayLimit` for scroll performance.
    var nsfwMode: NSFWMode {
        NSFWMode(rawValue: nsfwModeRaw) ?? .blur
    }

    private var emptyState: ShelfEmptyState? {
        ShelfEmptyState.evaluate(.init(
            hasStorage: appState.historyContainer != nil,
            visibleCount: displayedItems.count,
            isSearching: !appState.searchText.trimmingCharacters(in: .whitespaces).isEmpty,
            inCollection: appState.selectedCollectionID != nil,
            isPaused: appState.isCapturingPaused,
            captureBlocked: PasteboardCaptureAccess.current() == .blocked
        ))
    }

    /// The floating window hosts this grid with `copyOnly` or `pasteImmediately` (Settings → General); the shelf with
    /// neither. Which window's visibility, keys and Escape apply follows the host, not the paste behaviour.
    var isPinnedHost: Bool {
        GridHost(copyOnly: copyOnly, pasteImmediately: pasteImmediately) == .pinnedWindow
    }

    var detailSuppressed: Bool {
        DetailPopoverPolicy.isSuppressed(
            isLocked: appState.isHistoryLocked,
            isShelfVisible: isPinnedHost ? appState.isPinnedWindowVisible : appState.isOverlayVisible
        )
    }

    var displayedItems: [ClipboardItem] {
        Array(cachedFilteredItems.prefix(displayLimit))
    }

    var body: some View {
        VStack(spacing: 0) {
            KeyboardNavigationWrapper(
                focusedIndex: $focusedIndex,
                itemCount: displayedItems.count,
                isSearchActive: appState.isSearchActive,
                isOverlayVisible: isPinnedHost ? appState.isPinnedWindowVisible : appState.isOverlayVisible,
                isEditingCollection: appState.isEditingCollection,
                isConfirming: pendingDelete != nil,
                isLocked: appState.isHistoryLocked,
                onEscape: handleEscape,
                onDismissShelf: isPinnedHost ? nil : { appState.close() },
                onReturn: handleReturn,
                onSpace: handleSpace,
                onCharacterTyped: { char in
                    appState.searchText = char
                    appState.isSearchActive = true
                },
                onEscapeFromSearch: {
                    appState.isSearchActive = false
                },
                onArrowKey: {
                    keyboardRevealedID = displayedItems.indices.contains(focusedIndex)
                        ? displayedItems[focusedIndex].id : nil
                    scrollToFocused()
                },
                onPrevPinboard: { cyclePinboard(forward: false) },
                onNextPinboard: { cyclePinboard(forward: true) },
                onDelete: requestDeleteForKey,
                onSelectAll: selectAllShown,
                onReturnFromSearch: handleReturnFromSearch,
                onReturnPlainFromSearch: pastePlainFromSearch,
                cardSpan: cardDimensions.width + 8,
                onOpenSettings: { appState.openSettingsFromOverlay?() },
                onNewCollection: { appState.isCreatingCollection = true },
                onPasteAllSelected: pasteAllSelected,
                onPasteSelectedOneByOne: pasteSelectedOneByOne,
                onUndo: { appState.performUndo() },
                onRedo: { appState.performRedo() },
                searchTextIsEmpty: { appState.searchText.isEmpty },
                onPasteNth: pasteNth,
                onShowActions: {
                    let host = isPinnedHost ? "pinned" : "shelf"
                    let place = "host=\(host) focused=\(focusedIndex) of \(displayedItems.count)"
                    Task { await focusAnchor.showActionsWhenReady(context: place) }
                },
                onCopy: copyFocused,
                onAskFromSearch: { Task { await appState.askPesto() } },
                onShowHidden: showFocusedHidden,
                onConfirm: confirmDelete,
                onCancelConfirmation: { pendingDelete = nil },
                onSearch: { appState.isSearchActive = true },
                onSaveImage: saveFocusedImage,
                onQuickLook: quickLookFocused,
                onReturnPlain: pastePlainFocused,
                content: {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            cardStack
                        }
                        .scrollPosition($scrollPosition)
                        .reportsScrollOffset()
                        // The margin belongs to the scroll view, not the row: scrolling a card to the start then keeps
                        // it,
                        // where padding on the row let the first card sit flush against the screen edge.
                        .contentMargins(.horizontal, 16, for: .scrollContent)
                        .id(appState.selectedCollectionID)
                        .transition(collectionSwitchTransition)
                        .onChange(of: scrollRequest) { _, request in
                            guard let request else { return }
                            if request.animated {
                                withAnimation(Motion.animation(.snappy(duration: ShelfMotion.glide))) {
                                    proxy.scrollTo(request.id, anchor: .center)
                                }
                            } else {
                                proxy.scrollTo(request.id, anchor: .leading)
                            }
                        }
                    }
                    .onScrollPhaseChange { _, phase in
                        let scrolling = phase == .interacting || phase == .decelerating
                        if scrollState.isScrolling != scrolling { scrollState.isScrolling = scrolling }
                        if scrolling {
                            if keyboardRevealedID != nil { keyboardRevealedID = nil }
                            if pointerOrigin != nil { pointerOrigin = nil }
                            if scrollState.pointerHasMoved { scrollState.pointerHasMoved = false }
                        }
                    }
                    .onContinuousHover(coordinateSpace: .global) { phase in
                        guard case let .active(point) = phase, !scrollState.pointerHasMoved else { return }
                        guard let origin = pointerOrigin else { return pointerOrigin = point }
                        if DetailPopoverPolicy
                            .pointerMoved(from: origin, to: point) { scrollState.pointerHasMoved = true }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                        scrollState.menuOpened()
                    }
                    .onReceive(Publishers.MergeMany(AnimatedImageSettings.changes
                            .map { NotificationCenter.default.publisher(for: $0) }))
                    { _ in
                        scrollState.refreshAutoPlay()
                    }
                    .accessibilityLabel("Clips")
                        .accessibilityValue(CountText.clips(cachedFilteredItems.count))
                }
            )
            .animation(Motion.animation(ShelfMotion.switchEase), value: appState.selectedCollectionID)
            .frame(height: cardDimensions.height + ShelfHeight.liftRoom)
            .overlay {
                if let emptyState {
                    ShelfEmptyStateView(
                        state: emptyState,
                        query: appState.searchText.trimmingCharacters(in: .whitespaces),
                        onAction: { action in
                            switch action {
                            case .openPrivacySettings: PasteboardAccessSettings.open()
                            case .resumeCapturing: appState.resumeCapturing?()
                            }
                        }
                    )
                }
            }
        }
        .padding(.bottom, ShelfHeight.bottomSlot)
        .overlay(alignment: .bottomTrailing) {
            if !copyOnly, selection.count > 1 {
                actionBar
                    .disabled(pendingDelete != nil)
                    .padding(.trailing, 16)
                    .padding(.bottom, SelectionActionBar.bottomInset)
                    .transition(.opacity.combined(with: .offset(y: 8)).combined(with: .scale(
                        scale: 0.96, anchor: .bottomTrailing
                    )))
            }
        }
        .animation(Motion.animation(.pestoMove), value: selection.count > 1)
        .overlay {
            if let ids = pendingDelete {
                ZStack {
                    Color.clear.contentShape(Rectangle()).onTapGesture { pendingDelete = nil }
                    ShelfDeleteConfirmation(
                        count: ids.count, canUndo: deletionCanBeUndone(ids), onConfirm: confirmDelete
                    ) { pendingDelete = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(Motion.animation(.easeOut(duration: 0.15)), value: pendingDelete != nil)
        // Single consolidated handler — three separate handlers existed before, making it
        // hard to reason about ordering and easy to accidentally add a fourth.
        .onChange(of: appState.uiTestWalkRequest) { _, _ in walkShelfToEnd() }
        .onChange(of: appState.isOverlayVisible) { _, visible in
            guard !isPinnedHost else { return }
            keyboardRevealedID = nil
            pointerOrigin = nil
            scrollState.pointerHasMoved = false
            if visible {
                scrollToStart()
                focusedIndex = 0
                isPasting = false
                appState.isDragging = false
                appState.draggingItemID = nil
                displayLimit = 1000
                ShelfAnnouncement.opened(clipCount: cachedFilteredItems.count, isLocked: appState.isHistoryLocked)
            } else {
                appState.isSearchActive = false
                appState.isEditingCollection = false
                appState.isCreatingCollection = false
            }
        }
        .onChange(of: appState.undoGeneration) { _, _ in filterEditGeneration += 1 }
        .onChange(of: appState.searchText) { _, _ in
            displayLimit = 1000
            keyboardRevealedID = nil
        }
        .onChange(of: selection.count) { _, count in SelectionAnnouncement.announce(count: count) }
        .onChange(of: appState.isOverlayVisible) { _, visible in
            if !visible {
                revealedIDs = []
                hideSecretsGeneration += 1
                quickLookController.close()
            }
        }
        .onChange(of: appState.isHistoryLocked) { _, locked in
            if locked {
                hideSecretsGeneration += 1
                quickLookController.close()
            }
        }
        .task(id: appState.searchText) { await updateSemanticResults() }
        .onChange(of: appState.selectedCollectionID) { _, new in
            displayLimit = 1000
            previousCollectionID = new
        }
        .onChange(of: appState.isPinnedWindowVisible) { _, visible in
            guard isPinnedHost else { return }
            if !visible { hideSecretsGeneration += 1 }
            if visible {
                displayLimit = 1000
                focusedIndex = 0
                scrollToStart()
            }
        }
        .onChange(of: displayedItems.count) { _, count in
            // A clip deleted or filtered out under the focus must not leave it past the end of the shelf.
            if focusedIndex >= count { focusedIndex = max(0, count - 1) }
        }
        .onChange(of: focusedIndex) { _, idx in
            guard idx < displayedItems.count else { return }
            let item = displayedItems[idx]
            focusedID = item.id
            let color = item.sourceDominantColorHex.flatMap { Color(hex: $0) } ?? .clear
            onFocusChanged?(color, CGFloat(idx) / max(1, CGFloat(displayedItems.count - 1)))
            quickLookController.reconcileWithPanel()
            if quickLookController.isOpen {
                if ShelfKeyGate.quickLookAllowed(
                    isHidden: item.sensitivityRaw != nil,
                    isFilteredContent: item.isNSFW,
                    isPendingAnalysis: item.analysisPending,
                    isCoveredForSharing: isPrivacyBlurred
                ) {
                    quickLookController.show(item: item)
                } else {
                    quickLookController.close()
                }
            }
        }
        // Filter cache: compute once on appear, then only when inputs change.
        .onAppear {
            quickLookController.onStateChanged = { isOpen in
                appState.isQuickLookOpen = isOpen
            }
            quickLookController.onClose = {
                appState.onRestoreKeyFocus?()
            }
            applyFiltered(computeFiltered(), isUpdate: false)
        }
        .onChange(of: filterKey) { _, _ in applyFiltered(computeFiltered(), isUpdate: true) }
    }

    // MARK: - Card grid

    private var cardStack: some View {
        cardRow
    }

    private var cardRow: some View {
        let actions = cardActions
        return LazyHStack(spacing: 8) {
            ForEach(Array(displayedItems.enumerated()), id: \.element.id) { idx, item in
                cardView(for: item, at: idx)
                    .transition(cardTransition)
            }
            // Sentinel: when the last displayed card appears, load 500 more.
            // The guard prevents multi-fire in a single layout pass — without it,
            // onAppear can fire several times before the new displayLimit takes effect.
            if cachedFilteredItems.count > displayedItems.count {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
                    .onAppear {
                        guard cachedFilteredItems.count > displayLimit else { return }
                        displayLimit += 500
                    }
            }
        }
        // Without this label the LazyHStack is an unnamed "Other" node in the AX tree (SwiftUI
        // synthesizes a container element for it once it holds several buttons), which fails
        // AccessibilityAuditTests. The name stays, redundant with "Clips" or not.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard cards")
        .environment(\.cardActions, actions)
    }
}
