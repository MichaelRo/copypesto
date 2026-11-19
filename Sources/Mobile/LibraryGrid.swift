// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The clips of the chosen scope as Pesto cards on the theme's ground, filtered in place by the search text on the
/// history index. Only the cards on screen are built, so only their sealed previews are opened.
struct LibraryGrid: View {
    let store: HistoryStore
    let showsChipRow: Bool

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

    var body: some View {
        let ids = listing.ids
        let count = CardGridLayout.columnCount(width: rowWidth, isAccessibilitySize: typeSize.isAccessibilitySize)
        let cardWidth = CardGridLayout.cardWidth(rowWidth: rowWidth, columns: count)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if showsChipRow { LibraryChipRow() }
                if !appState.storeIsOnDisk { notSavedBanner }
                grid(ids, columns: count, cardWidth: cardWidth)
                    .environment(\.cardClock, minute)
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
        .background(ground.ignoresSafeArea())
        .overlay { LibraryEmptyState(isEmpty: hasListed && ids.isEmpty, hasClips: !store.items.isEmpty) }
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
            toggleDetail: toggleDetail
        ))
    }

    private var inCollection: Bool {
        if case .collection = library.filter.scope { return true }
        return false
    }

    private func grid(_ ids: [UUID], columns count: Int, cardWidth: CGFloat) -> some View {
        let animatesChange = listing.animates
        let columns = Array(repeating: GridItem(.flexible(), spacing: CardGridLayout.spacing), count: count)
        return LazyVGrid(columns: columns, spacing: CardGridLayout.spacing) {
            ForEach(ids, id: \.self) { id in
                if let item = store.item(for: id) {
                    ClipCard(
                        item: item, width: cardWidth, collections: collections, isFocused: focusedClip == id,
                        inCollection: inCollection, revision: ClipCard.Revision(item)
                    )
                    .focusable()
                    .focused($focusedClip, equals: id)
                    .focusEffectDisabled()
                    .id(CardIdentity(id: id, content: item.contentHash))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
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

    private var listingKey: LibraryListing.Key {
        LibraryListing.Key(
            revision: store.revision, query: library.query, filter: library.filter, isSearching: library.isSearching,
            orderVersion: library.orderVersion, textEdits: appState.textEdits, byMeaning: byMeaning,
            hidesSensitive: NSFWMode(rawValue: nsfwModeRaw) == .hide, smartRule: smartBoard?.smartPredicateData
        )
    }

    private func relist(_ key: LibraryListing.Key) {
        listing = LibraryListing.list(key, in: store, order: library.order, smartRule: smartRule)
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
    let content: String
}
