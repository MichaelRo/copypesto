// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import UIKit

/// The clips of the chosen scope as Pesto cards on the theme's ground, filtered in place by the search text on the
/// history index. Only the cards on screen are built, so only their sealed previews are opened.
struct LibraryGrid: View {
    let store: HistoryStore
    let showsChipRow: Bool
    var showsScopeChips = true

    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.pestoSurface) private var ground
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var rowWidth: CGFloat = 0
    @FocusState private var focusedClip: UUID?
    /// The minute the cards' ages are read at. A `TimelineView` around the grid kept the grid from drawing any change
    /// until its next tick (an edited card kept its old text), so one task moves this instead.
    @State private var minute = Date.now
    @State private var byMeaning: [UUID] = []
    @State private var listing = LibraryListing.Result(ids: [], animates: false)
    @State private var hasListed = false
    @State private var position: CardIdentity?
    @State private var hasRestoredPosition = false
    @State private var ranking = SemanticRanking()
    @AppStorage(Setting.nsfwMode) private var nsfwModeRaw: String
    @AppStorage(Setting.lockedCollections) private var lockedCollectionsStored: String
    @AppStorage(Setting.dismissedSnippetHint) private var dismissedSnippetHint: Bool

    var body: some View {
        let ids = listing.ids
        let count = CardGridLayout.columnCount(width: rowWidth, isAccessibilitySize: typeSize.isAccessibilitySize)
        let cardWidth = CardGridLayout.cardWidth(rowWidth: rowWidth, columns: count)
        VStack(spacing: 0) {
            if showsChipRow {
                LibraryChipRow(showsScopes: showsScopeChips)
                    .padding(.vertical, 6)
                    .background(ground)
                    .contentShape(.rect)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !appState.storeIsOnDisk { notSavedBanner }
                    if showsSnippetPlaceholderHint, !ids.isEmpty { snippetPlaceholderHint }
                    grid(ids, columns: count, cardWidth: cardWidth)
                        .environment(\.cardClock, minute)
                        .environment(\.peerDeviceNames, appState.peerDeviceNames)
                        .environment(\.sourceAppCatalog, appState.sourceApps)
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollPosition(id: $position, anchor: .top)
            .onChange(of: position) { _, first in if hasRestoredPosition { library.scrollAnchor = first } }
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                await SyncExchange.onPull(appState.sync)
                library.resort()
            }
            .overlay {
                if let locked = lockedScope {
                    LockedCollectionView(collectionID: locked)
                } else {
                    LibraryEmptyState(isEmpty: hasListed && ids.isEmpty, hasClips: !store.items.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if library.isSelecting {
                MobileSelectionBar(collections: collections, listing: listing)
            }
        }
        .background(ground.ignoresSafeArea())
        .onChange(of: listingKey, initial: true) { _, key in relist(key) }
        .libraryBanners()
        .sensoryFeedback(.success, trigger: library.copyCount)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                minute = .now
            }
        }
        .task(id: library.query) { await updateMeaningMatches() }
        .onDrop(of: ItemProviderCapture.acceptedTypes + [ClipDrag.clipIDType], isTargeted: nil) { providers in
            guard !ClipDrag.isOwnDrag(providers) else { return false }
            Task { await appState.add(from: providers, method: .drop) }
            return true
        }
        .focusedSceneValue(\.listCommands, ListCommandActions(
            newNote: { library.isComposing = true },
            search: { library.isSearching = true },
            toggleDetail: toggleDetail,
            copySelected: library.isSelecting ? copySelectedClosure() : nil
        ))
    }

    private func copySelectedClosure() -> (() -> Void)? {
        guard !library.isSearching,
              library.openClipID == nil,
              library.textEdit == nil,
              library.snippetEditor == nil else { return nil }
        let listing = listing
        return {
            guard !library.selectedClipIDs.isEmpty else { return }
            let textual: [ClipboardItem] = library.selectedClipIDs
                .sorted { (listing.indexByID[$0] ?? .max) < (listing.indexByID[$1] ?? .max) }
                .compactMap { id in
                    guard let item = store.item(for: id),
                          item.type == .text || item.type == .code else { return nil }
                    return item
                }
            guard textual.count >= 2 else { return }
            if appState.copyJoined(textual) { library.endSelection() }
        }
    }

    private var inCollection: Bool {
        if case .collection = library.filter.scope { return true }
        return false
    }

    private func grid(_ ids: [UUID], columns count: Int, cardWidth: CGFloat) -> some View {
        let animatesChange = listing.animates
        let columns = Array(repeating: GridItem(.flexible(), spacing: CardGridLayout.spacing), count: count)
        let cardHeight = CardGridLayout.cardHeight(forWidth: cardWidth)
        return LazyVGrid(columns: columns, spacing: CardGridLayout.spacing) {
            ForEach(ids, id: \.self) { id in
                if let item = store.item(for: id) {
                    SelectionAwareCard(
                        item: item,
                        width: cardWidth,
                        collections: collections,
                        isFocused: focusedClip == id,
                        inCollection: inCollection,
                        isFlashed: library.flashedClipID == id,
                        revision: ClipCard.Revision(item)
                    )
                    .focusable()
                    .focused($focusedClip, equals: id)
                    .focusEffectDisabled()
                    .id(CardIdentity(id: id))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .background {
            HorizontalSelectAttachment(
                isEnabled: library.isSelecting,
                itemCount: ids.count,
                columns: count,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                visibleIDs: ids,
                library: library
            )
        }
        .scrollTargetLayout()
        // A hardware keyboard's arrows move the focused card; Return copies it (`ClipCard`). At an edge the key is
        // left to the system.
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            let direction = GridFocusMove.direction(of: press.key, layout: layoutDirection)
            guard let current = focusedClip, let index = ids.firstIndex(of: current), let direction else {
                return .ignored
            }
            let next = GridFocusMove.target(from: index, count: ids.count, columns: count, moving: direction)
            guard let next else { return .ignored }
            focusedClip = ids[next]
            return .handled
        }
        .transaction(value: ids) { transaction in
            transaction.animation = animatesChange ? Motion.animation(.pestoMove) : nil
        }
        .padding(.horizontal, CardGridLayout.margin)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width - CardGridLayout.margin * 2
        } action: { width in
            rowWidth = width
        }
        .accessibilityIdentifier(MobileAccessibilityID.clipGrid)
    }

    /// The collection on screen when it is locked on this device and not opened (ADR 0081).
    private var lockedScope: UUID? {
        guard case let .collection(id) = library.filter.scope else { return nil }
        let lock = appState.secretReveal.collectionLock(locked: lockedCollectionsStored)
        return lock.isLocked(id) && !lock.isOpen(id) ? id : nil
    }

    private var listingKey: LibraryListing.Key {
        let hideNSFW = NSFWMode(rawValue: nsfwModeRaw) == .hide
            && !(library.isSearching && library.filter.sensitiveOnly)
        return LibraryListing.Key(
            revision: store.revision, query: library.query, filter: library.filter, isSearching: library.isSearching,
            orderVersion: library.orderVersion, textEdits: appState.textEdits, byMeaning: byMeaning,
            hidesSensitive: hideNSFW, smartRule: smartBoard?.smartPredicateData,
            collectionLock: appState.secretReveal.collectionLock(locked: lockedCollectionsStored)
        )
    }

    private func relist(_ key: LibraryListing.Key) {
        listing = HangDiagnostics.measure("libraryRelist") {
            LibraryListing.list(key, in: store, order: library.order, smartRule: smartRule)
        }
        library.visibleResultCount = listing.ids.count
        hasListed = true
        guard !hasRestoredPosition else { return }
        hasRestoredPosition = true
        position = library.scrollAnchor
    }

    /// Clips that match the query by meaning, found on the device with the same model and threshold as the Mac and
    /// shown after the text matches; with the model unavailable there are none.
    private func updateMeaningMatches() async {
        let query = library.query.trimmingCharacters(in: .whitespaces)
        guard SemanticSearch.asksForMeaning(query) else {
            byMeaning = []
            return
        }
        try? await Task.sleep(for: SemanticSearch.typingPause)
        guard !Task.isCancelled else { return }
        guard let container = appState.historyContainer else { return }
        let found = await ranking.matches(for: query, revision: store.revision, container: container)
        if !Task.isCancelled { byMeaning = found }
    }

    private var smartBoard: Pinboard? {
        guard case let .collection(id) = library.filter.scope,
              let board = collections.first(where: { $0.id == id }), board.isSmart else { return nil }
        return board
    }

    private var smartRule: ((UUID) -> Bool)? {
        guard let board = smartBoard, let data = board.smartPredicateData,
              let rules = try? SmartCollectionPredicate.decodeRuleSet(data),
              SmartCollectionPredicate.canCompileRuleSet(rules) else { return nil }
        let store = store
        return { id in store.item(for: id).map(rules.matches) ?? false }
    }

    private func toggleDetail() {
        if library.openClipID != nil {
            library.openClipID = nil
        } else if let focusedClip {
            library.open(focusedClip)
        }
    }

    private var showsSnippetPlaceholderHint: Bool {
        !dismissedSnippetHint && !library.isSearching && smartBoard?.isSnippetsSmartCollection == true
    }

    private var snippetPlaceholderHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "curlybraces")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Snippets fill in placeholders like {{date}} or {{name}} when copied.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                withAnimation(Motion.animation(.pestoQuick)) {
                    dismissedSnippetHint = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss hint")
        }
        .padding(.horizontal, CardGridLayout.margin)
    }

    private var notSavedBanner: some View {
        Label("Nothing is saved this session: the history could not be opened on disk.", systemImage: "bolt.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, CardGridLayout.margin)
    }
}

/// A card's identity in the grid: its clip and that clip's content, so an edited card is a new view.
struct CardIdentity: Hashable {
    let id: UUID
    var content = ""
}

private struct SelectionAwareCard: View {
    let item: ClipboardItem
    let width: CGFloat
    let collections: [Pinboard]
    let isFocused: Bool
    let inCollection: Bool
    let isFlashed: Bool
    let revision: ClipCard.Revision
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ClipCard(
            item: item,
            width: width,
            collections: collections,
            isFocused: isFocused,
            inCollection: inCollection,
            isSelected: library.isSelecting && library.selectedClipIDs.contains(item.id),
            isFlashed: isFlashed,
            revision: revision
        )
    }
}

private struct HorizontalSelectAttachment: UIViewRepresentable {
    let isEnabled: Bool
    let itemCount: Int
    let columns: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let visibleIDs: [UUID]
    let library: LibraryModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.gridView = uiView
        coordinator.isEnabled = isEnabled
        coordinator.itemCount = itemCount
        coordinator.columns = columns
        coordinator.cardWidth = cardWidth
        coordinator.cardHeight = cardHeight
        coordinator.visibleIDs = visibleIDs
        coordinator.library = library
        coordinator.attachIfNeeded(from: uiView)
        coordinator.panGesture?.isEnabled = isEnabled
        if !isEnabled {
            coordinator.reset()
        }
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.stopAutoScroll()
        if let pan = coordinator.panGesture, let scrollView = coordinator.attachedScrollView {
            scrollView.removeGestureRecognizer(pan)
        }
        coordinator.panGesture = nil
        coordinator.attachedScrollView = nil
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var gridView: UIView?
        weak var attachedScrollView: UIScrollView?
        var panGesture: UIPanGestureRecognizer?
        var isEnabled = false
        var itemCount = 0
        var columns = 2
        var cardWidth: CGFloat = 0
        var cardHeight: CGFloat = 0
        var visibleIDs: [UUID] = []
        weak var library: LibraryModel?

        private var anchorIndex: Int?
        private var lastAppliedIndex: Int?
        private var baseSelection: Set<UUID> = []
        private var selecting = true
        private let feedback = UISelectionFeedbackGenerator()
        private var displayLink: CADisplayLink?
        private var lastTickTimestamp: CFTimeInterval?
        private var lastViewportPoint: CGPoint?
        private var currentAutoScrollVelocity: CGFloat = 0

        func attachIfNeeded(from view: UIView) {
            guard attachedScrollView == nil else { return }
            var current = view.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                    pan.delegate = self
                    pan.maximumNumberOfTouches = 1
                    pan.cancelsTouchesInView = false
                    scrollView.addGestureRecognizer(pan)
                    attachedScrollView = scrollView
                    panGesture = pan
                    return
                }
                current = candidate.superview
            }
            Task { @MainActor [weak self, weak view] in
                await Task.yield()
                guard let self, let view, self.attachedScrollView == nil else { return }
                self.attachIfNeeded(from: view)
            }
        }

        func reset() {
            stopAutoScroll()
            lastViewportPoint = nil
            anchorIndex = nil
            lastAppliedIndex = nil
            baseSelection = []
        }

        func stopAutoScroll() {
            displayLink?.invalidate()
            displayLink = nil
            lastTickTimestamp = nil
            currentAutoScrollVelocity = 0
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let gridView else { return false }
            let velocity = pan.velocity(in: gridView)
            guard abs(velocity.x) > abs(velocity.y) * 1.5, abs(velocity.x) > 20 else { return false }
            let point = pan.location(in: gridView)
            return CardGridLayout.cardIndex(
                at: point,
                itemCount: itemCount,
                columns: columns,
                cardWidth: cardWidth,
                cardHeight: cardHeight
            ) != nil
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        )
        -> Bool {
            false
        }

        @objc
        private func handlePan(_ pan: UIPanGestureRecognizer) {
            guard isEnabled, let gridView, let library else {
                reset()
                return
            }
            let point = pan.location(in: gridView)
            switch pan.state {
            case .began:
                guard let startIndex = CardGridLayout.cardIndex(
                    at: point,
                    itemCount: itemCount,
                    columns: columns,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight
                ), visibleIDs.indices.contains(startIndex) else {
                    reset()
                    return
                }
                anchorIndex = startIndex
                lastAppliedIndex = startIndex
                baseSelection = library.selectedClipIDs
                selecting = !baseSelection.contains(visibleIDs[startIndex])
                feedback.prepare()
                library.applyDragSelection(
                    fromIndex: startIndex,
                    toIndex: startIndex,
                    in: visibleIDs,
                    baseSelection: baseSelection,
                    selecting: selecting
                )
                feedback.selectionChanged()
                updateAutoScroll(for: pan)

            case .changed:
                updateAutoScroll(for: pan)
                guard let anchor = anchorIndex else { return }
                applySelection(at: point, anchor: anchor, in: library)

            case .ended, .cancelled, .failed:
                reset()

            default:
                break
            }
        }

        private func applySelection(at gridPoint: CGPoint, anchor: Int, in library: LibraryModel) {
            guard let currentIndex = CardGridLayout.cardIndex(
                at: gridPoint,
                itemCount: itemCount,
                columns: columns,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                allowsGutter: true
            ), currentIndex != lastAppliedIndex else { return }
            lastAppliedIndex = currentIndex
            library.applyDragSelection(
                fromIndex: anchor,
                toIndex: currentIndex,
                in: visibleIDs,
                baseSelection: baseSelection,
                selecting: selecting
            )
            feedback.selectionChanged()
        }

        private func updateAutoScroll(for pan: UIPanGestureRecognizer) {
            guard let scrollView = attachedScrollView,
                  let viewportView = scrollView.superview else
            {
                stopAutoScroll()
                return
            }
            let touchPoint = pan.location(in: viewportView)
            lastViewportPoint = touchPoint
            let visibleMinY = scrollView.frame.minY + scrollView.adjustedContentInset.top
            let visibleMaxY = scrollView.frame.maxY - scrollView.adjustedContentInset.bottom
            let velocity = CardGridLayout.edgeAutoScrollVelocity(
                touchY: touchPoint.y,
                visibleMinY: visibleMinY,
                visibleMaxY: visibleMaxY
            )
            currentAutoScrollVelocity = velocity
            guard velocity != 0 else {
                stopAutoScroll()
                return
            }
            if displayLink == nil {
                lastTickTimestamp = nil
                let link = CADisplayLink(target: self, selector: #selector(handleAutoScrollTick(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }

        @objc
        private func handleAutoScrollTick(_ link: CADisplayLink) {
            guard isEnabled,
                  let anchor = anchorIndex,
                  let scrollView = attachedScrollView,
                  let viewportView = scrollView.superview,
                  let gridView,
                  let library,
                  let viewportPoint = lastViewportPoint,
                  currentAutoScrollVelocity != 0 else
            {
                stopAutoScroll()
                return
            }
            let dt: CGFloat = if let previous = lastTickTimestamp {
                min(1.0 / 20.0, max(0, CGFloat(link.timestamp - previous)))
            } else {
                1.0 / 60.0
            }
            lastTickTimestamp = link.timestamp

            let minY = -scrollView.adjustedContentInset.top
            let maxY = max(
                minY,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )
            let nextY = min(max(scrollView.contentOffset.y + currentAutoScrollVelocity * dt, minY), maxY)
            guard abs(nextY - scrollView.contentOffset.y) >= 0.25 else {
                stopAutoScroll()
                return
            }
            scrollView.contentOffset.y = nextY
            let gridPoint = gridView.convert(viewportPoint, from: viewportView)
            applySelection(at: gridPoint, anchor: anchor, in: library)
        }
    }
}
