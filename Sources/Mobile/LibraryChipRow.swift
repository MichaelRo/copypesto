// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

struct LibraryChipRow: View {
    @Environment(LibraryModel.self) private var library
    @Environment(MobileAppState.self) private var appState
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @AppStorage(Setting.hiddenMobileCollections) private var hiddenStored: String
    @State private var isAsking = false

    private var visibleCollections: [Pinboard] {
        let hidden = HiddenCollections.ids(from: hiddenStored)
        return collections.filter { !hidden.contains($0.id) }
    }

    var body: some View {
        let chips = LibraryChip.row(
            collectionIDs: collections.map(\.id), isSearching: library.isSearching,
            offersAsk: !library.query.trimmingCharacters(in: .whitespaces).isEmpty && !library.filter.hasAsk,
            hasAsk: library.filter.hasAsk,
            hiddenIDs: HiddenCollections.ids(from: hiddenStored)
        )
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    view(for: chip)
                }
            }
            .padding(.horizontal, CardGridLayout.margin)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier(MobileAccessibilityID.chipRow)
    }

    @ViewBuilder
    private func view(for chip: LibraryChip) -> some View {
        switch chip {
        case .all:
            chipButton(chip, label: String(localized: "All"), symbol: "tray.full")
        case .pinned:
            chipButton(chip, label: LibraryScope.pinned.title, symbol: "pin")
        case let .collection(id):
            if let board = collections.first(where: { $0.id == id }) {
                chipButton(
                    chip, label: board.name, symbol: board.symbolName,
                    tint: Color(hex: board.colorHex)
                )
                .contextMenu {
                    CollectionMenu(board: board, collections: visibleCollections, allowsHideOnPhone: true)
                }
            }
        case .newCollection:
            Button("New Collection", systemImage: "plus") { library.isNamingCollection = true }
                .labelStyle(.iconOnly)
                .buttonStyle(MobileChipStyle(isActive: false, tint: nil))
        case .divider:
            Divider().frame(height: 20)
        case let .kind(type):
            chipButton(chip, label: LibraryScope.kindTitle(type), symbol: type.presentation.symbolName)
        case let .date(chosen):
            chipButton(
                chip,
                label: chosen == .today ? String(localized: "Today") : String(localized: "This Week"),
                symbol: chosen == .today ? "sun.max" : "calendar"
            )
        case .otherDevices:
            chipButton(chip, label: String(localized: "Other Devices"), symbol: "laptopcomputer.and.iphone")
        case .ask:
            Button {
                Task { await ask() }
            } label: {
                HStack(spacing: 4) {
                    if isAsking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles").accessibilityHidden(true)
                    }
                    Text("Ask")
                }
            }
            .buttonStyle(MobileChipStyle(isActive: false, tint: nil))
            .disabled(isAsking)
            .accessibilityLabel(String(localized: "Ask Pesto"))
            .accessibilityInputLabels([Text("Ask"), Text("Ask Pesto")])
            .accessibilityHint(String(localized: "Turns what you typed into filters."))
            .accessibilityIdentifier(MobileAccessibilityID.askChip)
        case .asked:
            chipButton(chip, label: library.filter.askedSummary, symbol: "sparkles")
                .accessibilityIdentifier(MobileAccessibilityID.askedChip)
        }
    }

    private func ask() async {
        guard !isAsking else { return }
        let sentence = library.query
        isAsking = true
        defer { isAsking = false }
        let query = await appState.askPesto(sentence)
        _ = withAnimation(Motion.animation(.pestoQuick)) {
            library.applyAnswer(query, to: sentence, isLocked: appState.isHistoryLocked)
        }
    }

    private func chipButton(_ chip: LibraryChip, label: String, symbol: String, tint: Color? = nil) -> some View {
        let active = library.filter.isSelected(chip)
        return Button {
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
        .buttonStyle(MobileChipStyle(isActive: active, tint: tint))
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
