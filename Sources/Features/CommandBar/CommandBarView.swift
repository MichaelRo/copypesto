// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// swiftlint:disable type_body_length
/// Morphing command bar: pinboard chips at rest, transforms to a search field
/// on ⌘F or when the user starts typing.
struct CommandBarView: View {
    @Environment(\.pestoAccent) private var accent
    @Environment(AppState.self) var appState: AppState
    @Environment(\.modelContext) private var modelContext
    /// The window this bar is in; each publishes its own app chips (`AppState.appChipLists`).
    var host: GridHost = .shelf
    @Query(sort: \Pinboard.sortOrder) var pinboards: [Pinboard]
    @FocusState private var searchFocused: Bool
    /// Whether the recent searches are showing. Set from what changes it (focus, the text, the history), not read
    /// from a binding that only runs when something else happens to redraw the bar. It used to work only because
    /// `AppState` republished every second while the shelf was open.
    @State private var showsRecentSearches = false
    @AppStorage(Setting.searchHistory) private var searchHistoryRaw: String
    @AppStorage(Setting.shelfPosition) private var shelfPositionRaw: String
    @AppStorage(Setting.nsfwMode) var nsfwModeRaw: String
    @AppStorage(Setting.keepsRemoteCopies) var keepsRemoteCopies: Bool
    @State var suggestionsModel = CommandBarSuggestionsModel()
    /// Bumped by a chip's keyboard action to open that chip's menu.
    @State var openRequests: [String: Int] = [:]
    @State var chipLiveOrder: [UUID]?
    @State var chipInsertionBar: CollectionReorder.InsertionBar?
    @State var chipFrozenFrames: [UUID: CGRect]?
    @State var chipFrames: [UUID: CGRect] = [:]
    @State private var isAllDropTarget = false
    @State var chipsContentWidth: CGFloat?

    /// The tag currently selected via `@tag` search syntax, if any.
    var selectedTag: String? {
        let q = appState.searchText
        guard q.hasPrefix("@") else { return nil }
        return String(q.dropFirst())
    }

    private var searchHistory: [String] {
        SearchHistory.entries(from: searchHistoryRaw)
    }

    private var popoverArrowEdge: Edge {
        ShelfPosition(stored: shelfPositionRaw) == .underNotch ? .top : .bottom
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                if appState.isSearchActive {
                    // Opens from the search button's end of the bar. Focus is set the moment search starts, before this
                    // motion, so a key typed straight away goes into the field.
                    searchField
                        .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
                } else {
                    chipsRow
                        .transition(.opacity)
                }
            }
            .animation(Motion.animation(.pestoMove), value: appState.isSearchActive)

            if appState.isSearchActive {
                filterBar
                    .transition(.opacity.animation(Motion.animation(.pestoQuick.delay(0.06))))
            }
        }
        .animation(Motion.animation(.pestoMove), value: appState.isSearchActive)
        .onChange(of: appChips, initial: true) { appState.appChipLists[host] = appChips }
        .onAppear { suggestionsModel.start(appState) }
        .onDisappear { suggestionsModel.stop() }
        .onChange(of: appState.isOverlayVisible) { _, visible in if visible { suggestionsModel.refresh() } }
        .onChange(of: appState.isPinnedWindowVisible) { _, visible in if visible { suggestionsModel.refresh() } }
        .onChange(of: appState.isHistoryLocked) { _, _ in suggestionsModel.refresh() }
        .onChange(of: appState.isSearchActive) { _, active in
            if active {
                SearchFieldCaret.arm()
                searchFocused = true
                Task {
                    try? await Task.sleep(for: .milliseconds(40))
                    SearchFieldCaret.placeAtEnd()
                }
            } else {
                searchFocused = false
                showsRecentSearches = false
                appState.searchText = ""
                appState.filterChipCursor = nil
                appState.clearSearchFilters()
            }
        }
    }

    var scrollableChips: some View {
        let creating = appState.isCreatingCollection
        return HStack(spacing: 8) {
            CollectionChip(
                name: "All",
                symbolName: "tray.full",
                color: .primary,
                isSelected: appState.selectedCollectionID == nil,
                spokenName: "All collections"
            ) {
                appState.selectedCollectionID = nil
            }
            .id(Self.allChipID)
            .overlay { if isAllDropTarget, appState.isDragging { Capsule().strokeBorder(
                Color.primary.opacity(0.5),
                lineWidth: 1.5
            ) } }
            .onDrop(of: [UTType.data], isTargeted: $isAllDropTarget) { _ in
                guard let itemID = appState.draggingItemID else { return false }
                moveItem(id: itemID, toCollectionID: nil)
                appState.draggingItemID = nil
                return true
            }

            ForEach(shownPinboards) { pinboard in
                PinboardChipView(
                    pinboard: pinboard,
                    isSelected: appState.selectedCollectionID == pinboard.id,
                    onSelect: { appState.selectedCollectionID = pinboard.id },
                    onDuplicate: { duplicatePinboard(pinboard) },
                    onExport: { appState.exportCollection?(pinboard.id) },
                    onSave: { name, symbol, colorHex in
                        let unique = CollectionNaming.uniqueName(
                            name, existing: pinboards.map(\.name), excluding: pinboard.name
                        )
                        appState.attempt("Couldn\u{2019}t save the collection") {
                            try appState.collectionStore(context: modelContext).edit(.edit, [pinboard]) {
                                pinboard.name = unique
                                pinboard.symbolName = symbol
                                pinboard.colorHex = colorHex
                            }
                        }
                    },
                    onDelete: { deletePinboard(pinboard) },
                    onDrop: {
                        if let id = appState.draggingItemID { moveItem(id: id, toCollectionID: pinboard.id) }
                    },
                    onMove: { movePinboard(pinboard.id, by: $0) },
                    canMoveLeft: pinboards.first?.id != pinboard.id,
                    canMoveRight: pinboards.last?.id != pinboard.id,
                    insertionSide: chipInsertionBar?.target == pinboard.id ? chipInsertionBar?.side : nil
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            if appState.isCreatingCollection {
                InlineCollectionCreator(isPresented: Binding(
                    get: { appState.isCreatingCollection }, set: { appState.isCreatingCollection = $0 }
                )) { name, symbol in
                    let next = (pinboards.map(\.sortOrder).max() ?? -1) + 1
                    let new = Pinboard(
                        name: CollectionNaming.uniqueName(name, existing: pinboards.map(\.name)),
                        symbolName: symbol,
                        colorHex: CollectionPalette.nextUnused(used: pinboards.map(\.colorHex)),
                        sortOrder: next,
                        isSmart: false,
                        smartPredicateData: nil,
                        triggerBundleID: nil
                    )
                    appState.attempt("Couldn\u{2019}t add the collection") {
                        try appState.collectionStore(context: modelContext).insert(.create, [new])
                    }
                    appState.selectedCollectionID = new.id
                }
                .id(Self.creatorID)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            if !suggestionsModel.suggestions.topTags.isEmpty {
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 2)
                ForEach(suggestionsModel.suggestions.topTags, id: \.self) { tag in
                    tagChip(tag)
                }
            }
        }
        .animation(Motion.animation(.pestoMove), value: creating)
        .animation(Motion.animation(.pestoPop), value: pinboards.map(\.id))
        .animation(Motion.animation(.pestoQuick), value: appState.draggingPinboardID)
        .animation(Motion.animation(.pestoQuick), value: chipInsertionBar)
        .onChange(of: appState.draggingPinboardID) { _, id in
            if id == nil {
                chipLiveOrder = nil
                chipInsertionBar = nil
                chipFrozenFrames = nil
            }
        }
        .coordinateSpace(name: ChipFramesKey.space)
        .onPreferenceChange(ChipFramesKey.self) { chipFrames = $0 }
        .background { chipRowDropLayer }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Collections and filters")
        .frame(minHeight: 26)
    }

    var rightToolbar: some View {
        HStack(spacing: 4) {
            Button {
                appState.isSearchActive = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .modifier(SearchGlyphTarget())
                    .pestoQuiet()
            }
            .modifier(SearchButtonStyle())
            .help("Search (⌘F)")
            .accessibilityLabel("Search")
            .accessibilityIdentifier(AccessibilityID.searchButton)

            Button {
                guard !appState.isCreatingCollection else { return }
                withAnimation(Motion.animation()) { appState.isCreatingCollection = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .modifier(SearchGlyphTarget())
                    .pestoQuiet()
            }
            .modifier(SearchButtonStyle())
            .contextMenu {
                Button("Import Collection\u{2026}") { appState.importCollection?() }
            }
            .help("New collection")
            .accessibilityLabel("New collection")
            .accessibilityIdentifier(AccessibilityID.newCollectionButton)

            ShelfWindowButtons()
        }
        .padding(.leading, 6)
    }

    private func tagChip(_ tag: String) -> some View {
        let isSelected = selectedTag?.lowercased() == tag.lowercased()
        return PestoChip(
            label: "@\(tag)",
            tint: Color(hue: stableHue(for: tag), saturation: 0.7, brightness: 0.85),
            isActive: isSelected,
            helpText: String(localized: "Filter by tag: \(tag)")
        ) {
            if isSelected {
                appState.searchText = ""
            } else {
                appState.searchText = "@\(tag)"
                appState.isSearchActive = false
            }
        }
        .accessibilityIdentifier(AccessibilityID.tagChip(tag))
    }

    // MARK: - Filter bar

    /// One filter chip: what it shows, what it does and how it is spoken. The bar draws them and Tab walks them.
    struct FilterEntry {
        let id: String
        let label: String
        /// What a test and VoiceOver find the chip by when its label changes with its state.
        var identifier: String?
        var icon: String?
        var iconImage: NSImage?
        var spoken: String?
        var help: String?
        let isActive: Bool
        var menu: [PopUpMenuItem]?
        let toggle: () -> Void
    }

    private var typeEntries: [FilterEntry] {
        ClipboardType.allCases.map { type in
            let rawType = type.rawValue
            let (label, icon) = type.presentation
            return FilterEntry(
                id: "type-\(rawType)", label: label, icon: icon, isActive: appState.searchTypeFilter.contains(rawType)
            ) {
                if appState.searchTypeFilter.contains(rawType) {
                    appState.searchTypeFilter.remove(rawType)
                } else {
                    appState.searchTypeFilter.insert(rawType)
                }
            }
        }
    }

    /// Every chip in the order Tab walks them.
    private var allFilterEntries: [FilterEntry] {
        typeEntries + [formatEntry] + dayEntries + [whenMoreEntry] + (fromEntry.map { [$0] } ?? []) + [sensitiveEntry] +
            remoteEntries +
            hiddenEntries
    }

    private var filterBar: some View {
        let entries = allFilterEntries
        let indexOf = Dictionary(entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        /// One row: the groups are told apart by a thin divider, and named for VoiceOver (a sighted person reads the
        /// chips themselves).
        func group(_ caption: LocalizedStringKey, id: String, _ group: [FilterEntry]) -> some View {
            HStack(spacing: 4) {
                ForEach(group, id: \.id) { filterChip($0, hasCursor: appState.filterChipCursor == indexOf[$0.id]) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(caption)
            .accessibilityIdentifier(AccessibilityID.filterGroup(id))
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 10) {
                group("Kind", id: "Kind", typeEntries)

                filterGroupDivider
                group("Format", id: "Format", [formatEntry])

                filterGroupDivider
                group("When", id: "When", dayEntries + [whenMoreEntry])

                if let fromEntry {
                    filterGroupDivider
                    group("From", id: "From", [fromEntry])
                }

                filterGroupDivider
                group("Other", id: "Other", [sensitiveEntry] + remoteEntries + hiddenEntries)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3) // room for the keyboard ring the scroll view clipped; taken back below
        }
        .padding(.vertical, -3)
        .onChange(of: entries.map(\.id)) { _, _ in registerFilterChipActions() }
        .onChange(of: appState.noResultsAdvice) { _, _ in registerFilterChipActions() }
        .onAppear { registerFilterChipActions() }
    }

    private var filterGroupDivider: some View {
        Divider().frame(height: 16).accessibilityHidden(true)
    }

    /// Hands the keyboard the chips as they are now, so Tab and Return can act on them (`AppState.filterChipActions`).
    private func registerFilterChipActions() {
        let entries = allFilterEntries
        let actions = entries.map { entry in
            FilterChipAction(
                spokenName: entry.spoken ?? entry.label,
                isActive: { [appState] in currentlyActive(entry.id, appState: appState) },
                toggle: entry.toggle
            )
        } + [appState.noResultsChipAction()].compactMap(\.self)
        appState.filterChipActions = actions
        appState.filterChipCursor = FilterChipCursor.kept(appState.filterChipCursor, count: actions.count)
    }

    /// A chip's state read when it is spoken, after its toggle ran (the entry's own `isActive` is a snapshot).
    private func currentlyActive(_ id: String, appState: AppState) -> Bool {
        switch id {
        case "sensitive": appState.searchSensitiveOnly
        case "remote": appState.searchRemoteOnly
        case "hidden": appState.showHiddenNSFW
        case let id where id.hasPrefix("type-"): appState.searchTypeFilter.contains(String(id.dropFirst(5)))
        case Self.fromID: !appState.searchSourceFilter.isEmpty
        case Self.formatID: formatEntry.isActive
        case "date-today": appState.searchDateFilter == .today
        case "date-yesterday": appState.searchDateFilter == .yesterday
        case Self.whenMoreID: ![SearchDateFilter.all, .today, .yesterday].contains(appState.searchDateFilter)
        case let id where id.hasPrefix("app-"): appState.searchSourceFilter.contains(String(id.dropFirst(4)))
        default: false
        }
    }

    private func filterChip(_ entry: FilterEntry, hasCursor: Bool) -> some View {
        PestoChip(
            label: entry.label, icon: entry.icon, iconImage: entry.iconImage, isActive: entry.isActive,
            hasKeyboardCursor: hasCursor, helpText: entry.help ?? "",
            menuItems: entry.menu, openRequest: openRequests[entry.id] ?? 0, action: entry.toggle
        )
        .accessibilityLabel(entry.spoken ?? entry.label)
        .accessibilityIdentifier(AccessibilityID.filterChip(entry.identifier ?? entry.label))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            searchInput
            searchTrailingButtons
        }
    }

    private var searchInput: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .pestoQuiet()

            TextField("Search clips…", text: Binding(get: { appState.searchText }, set: { appState.searchText = $0 }))
                .accessibilityIdentifier(AccessibilityID.searchField)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .task {
                    // The field is inserted in the same update that flips isSearchActive; focusing in that pass
                    // finds no field, so wait a beat.
                    try? await Task.sleep(for: .milliseconds(60))
                    searchFocused = true
                    try? await Task.sleep(for: .milliseconds(40))
                    SearchFieldCaret.placeAtEnd()
                    try? await Task.sleep(for: .milliseconds(110))
                    refreshRecentSearches()
                }
                .onSubmit { saveToHistory(appState.searchText) }
                .onChange(of: searchFocused) { _, focused in
                    guard focused else { return refreshRecentSearches() }
                    // A popover asked for before its field is in a window is dropped, and asking again with the same
                    // value does nothing, so it is turned on only once the field has had a moment to attach.
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        refreshRecentSearches()
                    }
                }
                .onChange(of: appState.searchText) { _, _ in refreshRecentSearches() }
                .onChange(of: searchHistoryRaw) { _, _ in refreshRecentSearches() }
                .popover(
                    isPresented: Binding(get: { showsRecentSearches }, set: recentSearchesPopoverChanged),
                    arrowEdge: popoverArrowEdge
                ) {
                    RecentSearchesList(queries: searchHistory) { query in
                        appState.searchText = query
                        showsRecentSearches = false
                    }
                }

            if !appState.searchText.isEmpty {
                Button {
                    appState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .pestoQuiet()
                        .pestoHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier(AccessibilityID.searchClearButton)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.searchFieldFrame)
    }

    private var searchTrailingButtons: some View {
        HStack(spacing: 8) {
            if looksLikeQuestion {
                Button {
                    Task { await ask() }
                } label: {
                    Label("Ask", systemImage: "sparkles").font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Turn this into filters (⌘Return)")
                .accessibilityIdentifier(AccessibilityID.askButton)
            }

            Button("Cancel") { deactivateSearch() }
                .pestoQuiet()
                .font(.subheadline)
                .accessibilityIdentifier(AccessibilityID.searchCancelButton)
        }
    }

    private var looksLikeQuestion: Bool {
        AskHeuristic.looksLikeQuestion(appState.searchText)
    }

    private func ask() async {
        saveToHistory(appState.searchText)
        await appState.askPesto()
    }

    /// Dismissing the popover marks it closed so it stays dismissed during the current typing pass.
    private func recentSearchesPopoverChanged(_ isShowing: Bool) {
        showsRecentSearches = isShowing
    }

    private func refreshRecentSearches() {
        let offered = appState.offersRecentSearches(searchFocused, history: searchHistory)
        if offered != showsRecentSearches { showsRecentSearches = offered }
    }

    private func deactivateSearch() {
        saveToHistory(appState.searchText)
        appState.isSearchActive = false
    }

    private func saveToHistory(_ query: String) {
        guard !appState.isHistoryLocked else { return }
        searchHistoryRaw = SearchHistory.recording(query, in: searchHistoryRaw)
    }

    private func moveItem(id: UUID, toCollectionID collectionID: UUID?) {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        appState.clipEditor(context: modelContext).edit(item) { $0.collectionID = collectionID }
    }

    private func duplicatePinboard(_ source: Pinboard) {
        let next = (pinboards.map(\.sortOrder).max() ?? -1) + 1
        let copy = Pinboard(
            name: CollectionNaming.copyName(of: source.name, existing: pinboards.map(\.name)),
            symbolName: source.symbolName,
            colorHex: source.colorHex,
            sortOrder: next,
            isSmart: source.isSmart,
            smartPredicateData: source.smartPredicateData,
            triggerBundleID: nil
        )
        appState.attempt("Couldn\u{2019}t duplicate the collection") {
            try appState.collectionStore(context: modelContext).insert(.duplicate, [copy])
        }
    }

    private func deletePinboard(_ pinboard: Pinboard) {
        appState.deleteCollection(id: pinboard.id, fromShelf: true)
    }

    /// Collection chips stay in place while one is dragged; `chipInsertionBar` marks where it will land.
    var shownPinboards: [Pinboard] {
        pinboards
    }

    func persistPinboardOrder(_ order: [UUID], moved id: UUID? = nil) {
        let ids = pinboards.map(\.id)
        guard order != ids else { return }
        let reordered = order.compactMap { id in pinboards.first { $0.id == id } }
        appState.attempt("Couldn\u{2019}t save the collection order") {
            try appState.collectionStore(context: modelContext).edit(.reorder, reordered) {
                for (i, p) in reordered.enumerated() {
                    p.sortOrder = i
                }
            }
        }
        if let id,
           let position = order.firstIndex(of: id),
           let name = pinboards.first(where: { $0.id == id })?.name
        {
            Announcer.announce("\(name), position \(position + 1) of \(order.count)")
        } else {
            Announcer.announce("Moved")
        }
    }

    private func movePinboard(_ id: UUID, by offset: Int) {
        let ids = pinboards.map(\.id)
        guard let from = ids.firstIndex(of: id), ids.indices.contains(from + offset) else { return }
        var order = ids
        order.swapAt(from, from + offset)
        withAnimation(Motion.animation(.pestoMove)) { persistPinboardOrder(order, moved: id) }
    }
}

// MARK: - Helpers

/// FNV-1a fold — deterministic, stable across process launches (unlike String.hashValue).
private func stableHue(for tag: String) -> Double {
    let hash = tag.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
    return Double(hash & 0xFFFF) / 65_536.0
}

// MARK: - Search button style

struct SearchButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(ShelfBarButtonStyle())
    }
}

// swiftlint:enable type_body_length
