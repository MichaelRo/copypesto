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
    @Environment(\.pestoSurface) private var ground
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var rowWidth: CGFloat = 0
    @FocusState private var focusedClip: UUID?

    var body: some View {
        let ids = visibleIDs()
        let count = CardGridLayout.columnCount(width: rowWidth, isAccessibilitySize: typeSize.isAccessibilitySize)
        let cardWidth = CardGridLayout.cardWidth(rowWidth: rowWidth, columns: count)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if showsChipRow { LibraryChipRow() }
                if !appState.storeIsOnDisk { notSavedBanner }
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    grid(ids, columns: count, cardWidth: cardWidth)
                        .environment(\.cardClock, timeline.date)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await SyncExchange.onPull(appState.sync)
            library.resort()
        }
        .background(ground.ignoresSafeArea())
        .overlay { LibraryEmptyState(isEmpty: ids.isEmpty, hasClips: !store.items.isEmpty) }
        .libraryBanners()
        .sensoryFeedback(.success, trigger: library.copyCount)
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

    private func grid(_ ids: [UUID], columns count: Int, cardWidth: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: CardGridLayout.spacing), count: count)
        return LazyVGrid(columns: columns, spacing: CardGridLayout.spacing) {
            ForEach(ids, id: \.self) { id in
                if let item = store.item(for: id) {
                    ClipCard(
                        item: item, width: cardWidth, collections: collections, isFocused: focusedClip == id,
                        revision: ClipCard.Revision(item)
                    )
                    .focusable()
                    .focused($focusedClip, equals: id)
                    .focusEffectDisabled()
                }
            }
        }
        .padding(.horizontal, CardGridLayout.margin)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width - CardGridLayout.margin * 2
        } action: { width in
            rowWidth = width
        }
        .accessibilityIdentifier(MobileAccessibilityID.clipGrid)
    }

    private func visibleIDs() -> [UUID] {
        _ = store.items.count
        _ = library.orderVersion
        guard let index = store.searchIndex() else { return [] }
        let kind = library.isSearching ? library.filter.kind : nil
        let fresh = library.filter.scope.ids(
            in: index,
            query: library.query,
            kind: kind,
            smartRule: smartRule,
            hidesSensitive: NSFWMode.current() == .hide
        )
        let context = "\(library.filter.scope)|\(library.query)|\(kind?.rawValue ?? "")"
        return library.order.arrange(fresh, context: context)
    }

    private var smartRule: ((UUID) -> Bool)? {
        guard case let .collection(id) = library.filter.scope,
              let board = collections.first(where: { $0.id == id }), board.isSmart,
              let data = board.smartPredicateData,
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
