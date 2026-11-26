// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

struct LibraryChipRow: View {
    var showsScopes = true

    @Environment(LibraryModel.self) private var library
    @Environment(MobileAppState.self) private var appState
    @Environment(\.pestoAccent) private var accent
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @AppStorage(Setting.hiddenMobileCollections) private var hiddenStored: String
    @AppStorage(Setting.lockedCollections) private var lockedStored: String
    @State private var showsCustomDateRange = false

    private var visibleCollections: [Pinboard] {
        let hidden = HiddenCollections.ids(from: hiddenStored)
        return collections.filter { !hidden.contains($0.id) }
    }

    private var availableApps: [SourceApp] {
        library.availableApps(in: appState.historyStore)
    }

    var body: some View {
        let apps = availableApps
        let chips = LibraryChip.row(
            collectionIDs: collections.map(\.id), isSearching: library.isSearching,
            offersAsk: library.canOfferAsk,
            hasAsk: library.filter.hasAsk,
            hiddenIDs: HiddenCollections.ids(from: hiddenStored),
            showsScopes: showsScopes,
            showsFrom: !apps.isEmpty || library.filter.sourceBundleID != nil
        )
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        view(for: chip, apps: apps)
                    }
                }
            }
            .padding(.horizontal, CardGridLayout.margin)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(MobileAccessibilityID.chipRow)
        .sheet(isPresented: $showsCustomDateRange) {
            CustomDateRangeSheet(
                initial: library.filter.effectiveDateFilter,
                onApply: { range in
                    library.cancelAsk()
                    withAnimation(Motion.animation(.pestoQuick)) {
                        library.filter.chooseDate(range)
                    }
                },
                onClear: {
                    library.cancelAsk()
                    withAnimation(Motion.animation(.pestoQuick)) {
                        library.filter.chooseDate(.all)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func view(for chip: LibraryChip, apps: [SourceApp]) -> some View {
        switch chip {
        case .all, .pinned, .collection, .newCollection, .scopeDivider, .filterDivider:
            scopeChipView(for: chip)
        case .kind, .when, .from, .sensitive, .otherDevices, .ask, .asked:
            filterChipView(for: chip, apps: apps)
        }
    }

    @ViewBuilder
    private func scopeChipView(for chip: LibraryChip) -> some View {
        switch chip {
        case .all:
            chipButton(chip, label: String(localized: "All"), symbol: "tray.full")
        case .pinned:
            chipButton(chip, label: LibraryScope.pinned.title, symbol: "pin")
        case let .collection(id):
            if let board = collections.first(where: { $0.id == id }) {
                let isLocked = LockedCollections.ids(from: lockedStored).contains(id)
                chipButton(
                    chip, label: board.name, symbol: isLocked ? "lock.fill" : board.symbolName,
                    tint: Color(hex: board.colorHex)
                )
                .accessibilityValue(isLocked ? String(localized: "Locked") : "")
                .contextMenu {
                    CollectionMenu(board: board, collections: visibleCollections, allowsHideOnPhone: true)
                }
            }
        case .newCollection:
            Button("New Collection", systemImage: "plus") { library.isNamingCollection = true }
                .labelStyle(.iconOnly)
                .buttonStyle(MobileChipStyle(isActive: false, tint: nil, usesGlass: true))
                .contextMenu {
                    Button("New Collection", systemImage: "plus") { library.isNamingCollection = true }
                    Button("Import Collection\u{2026}", systemImage: "square.and.arrow.down") {
                        library.isImportingCollection = true
                    }
                }
        case .scopeDivider, .filterDivider:
            Divider().frame(height: 20)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func filterChipView(for chip: LibraryChip, apps: [SourceApp]) -> some View {
        switch chip {
        case let .kind(type):
            chipButton(chip, label: LibraryScope.kindTitle(type), symbol: type.presentation.symbolName)
        case .when:
            whenMenuChip
        case .from:
            fromMenuChip(apps: apps)
        case .sensitive:
            chipButton(chip, label: String(localized: "Sensitive"), symbol: "eye.slash")
                .accessibilityIdentifier(MobileAccessibilityID.sensitiveChip)
        case .otherDevices:
            chipButton(chip, label: String(localized: "Other Devices"), symbol: "laptopcomputer.and.iphone")
        case .ask:
            askChipButton
        case .asked:
            chipButton(chip, label: library.filter.askedSummary, symbol: "sparkles")
                .accessibilityIdentifier(MobileAccessibilityID.askedChip)
        default:
            EmptyView()
        }
    }

    private var askChipButton: some View {
        let isQuestion = AskHeuristic.looksLikeQuestion(library.query)
        return Button {
            library.startAsk(
                using: { await appState.askPesto($0) },
                isLocked: { appState.isHistoryLockedNow() }
            )
        } label: {
            HStack(spacing: 4) {
                if library.isAsking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles").accessibilityHidden(true)
                }
                Text("Ask")
            }
            .foregroundStyle(isQuestion ? accent : .primary)
        }
        .buttonStyle(MobileChipStyle(isActive: false, tint: isQuestion ? accent : nil, usesGlass: true))
        .overlay {
            if isQuestion {
                Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1)
                    .padding(.vertical, (TouchTarget.minimum - 34) / 2)
            }
        }
        .disabled(library.isAsking)
        .accessibilityLabel(String(localized: "Ask Pesto"))
        .accessibilityInputLabels([Text("Ask"), Text("Ask Pesto")])
        .accessibilityHint(String(localized: "Turns what you typed into filters."))
        .accessibilityIdentifier(MobileAccessibilityID.askChip)
    }

    private var whenMenuChip: some View {
        let active = library.filter.dateFilter != .all
        let label = active ? library.filter.dateFilter.label() : String(localized: "When")
        return Menu {
            whenOption(String(localized: "Any Time"), filter: .all)
            whenOption(String(localized: "Today"), filter: .today)
            whenOption(String(localized: "Yesterday"), filter: .yesterday)
            whenOption(String(localized: "Last 7 Days"), filter: .week)
            whenOption(String(localized: "Last 30 Days"), filter: .month)
            Divider()
            whenOption(String(localized: "Last Hour"), filter: .last(3600))
            whenOption(String(localized: "Last 3 Hours"), filter: .last(3 * 3600))
            whenOption(String(localized: "Last 12 Hours"), filter: .last(12 * 3600))
            Divider()
            Button("Custom Date Range\u{2026}", systemImage: "calendar.badge.plus") {
                showsCustomDateRange = true
            }
        } label: {
            menuChipLabel(label, symbol: "calendar", active: active)
        }
        .buttonStyle(MobileChipStyle(isActive: active, tint: nil, usesGlass: true))
        .accessibilityLabel(active ? String(localized: "When, \(label)") : String(localized: "When"))
        .accessibilityIdentifier(MobileAccessibilityID.whenChip)
    }

    private func whenOption(_ title: String, filter: SearchDateFilter) -> some View {
        Button {
            library.cancelAsk()
            withAnimation(Motion.animation(.pestoQuick)) {
                library.filter.chooseDate(filter)
            }
        } label: {
            if library.filter.dateFilter == filter {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func fromMenuChip(apps: [SourceApp]) -> some View {
        let selected = apps.first { $0.bundleID == library.filter.sourceBundleID }
        let active = library.filter.sourceBundleID != nil
        let selectedName = selected?.name
            ?? library.filter.sourceBundleID.flatMap { library.appName(for: $0, in: appState.historyStore) }
        let label = active ? (selectedName ?? String(localized: "Selected App")) : String(localized: "From")
        return Menu {
            if active {
                Button("Any App") {
                    library.cancelAsk()
                    withAnimation(Motion.animation(.pestoQuick)) {
                        library.filter.chooseSource(nil)
                    }
                }
                Divider()
            }
            ForEach(apps, id: \.bundleID) { app in
                Button {
                    library.cancelAsk()
                    withAnimation(Motion.animation(.pestoQuick)) {
                        library.filter.chooseSource(app.bundleID)
                    }
                } label: {
                    let itemTitle = "\(app.name) \u{00B7} \(app.count)"
                    if library.filter.sourceBundleID == app.bundleID {
                        Label(itemTitle, systemImage: "checkmark")
                    } else {
                        Text(itemTitle)
                    }
                }
            }
        } label: {
            menuChipLabel(label, symbol: "app.badge", active: active)
        }
        .buttonStyle(MobileChipStyle(isActive: active, tint: nil, usesGlass: true))
        .accessibilityLabel(active ? String(localized: "From, \(label)") : String(localized: "From"))
        .accessibilityIdentifier(MobileAccessibilityID.fromChip)
    }

    private func menuChipLabel(_ label: String, symbol: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            if active {
                Image(systemName: "checkmark").font(.caption2.weight(.bold)).accessibilityHidden(true)
            }
            CollectionIcon(symbol: symbol).accessibilityHidden(true)
            Text(label).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).accessibilityHidden(true)
        }
    }

    private func chipButton(_ chip: LibraryChip, label: String, symbol: String, tint: Color? = nil) -> some View {
        let active = library.filter.isSelected(chip)
        return Button {
            library.cancelAsk()
            withAnimation(Motion.animation(.pestoQuick)) { library.filter.choose(chip) }
        } label: {
            HStack(spacing: 4) {
                if active {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).accessibilityHidden(true)
                }
                CollectionIcon(symbol: symbol).accessibilityHidden(true)
                Text(label).lineLimit(1)
            }
        }
        .buttonStyle(MobileChipStyle(isActive: active, tint: tint, usesGlass: true))
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
