// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The clips of one scope, filtered by the search text on the history index. On iPad it drives the split view's
/// selection; on iPhone each row pushes the clip.
struct ClipListView: View {
    let store: HistoryStore
    let scope: LibraryScope
    let query: String
    var selection: Binding<UUID?>?
    var onSearch: () -> Void = {}

    @Environment(MobileAppState.self) private var appState
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var isComposing = false

    var body: some View {
        let ids = visibleIDs()
        list(ids)
            .accessibilityIdentifier(MobileAccessibilityID.clipList)
            .overlay { emptyState(isEmpty: ids.isEmpty) }
            .toolbar { captureToolbar }
            .onDrop(of: ItemProviderCapture.acceptedTypes, isTargeted: nil) { providers in
                Task { await appState.add(from: providers) }
                return true
            }
            .sheet(isPresented: $isComposing) { NewNoteView() }
            .focusedSceneValue(\.listCommands, ListCommandActions(newNote: { isComposing = true }, search: onSearch))
    }

    private func visibleIDs() -> [UUID] {
        _ = store.items.count
        guard let index = store.searchIndex() else { return [] }
        return scope.ids(
            in: index, query: query, smartRule: smartRule, hidesSensitive: NSFWMode.current() == .hide
        )
    }

    private var smartRule: ((UUID) -> Bool)? {
        guard case let .collection(id) = scope,
              let board = collections.first(where: { $0.id == id }), board.isSmart,
              let data = board.smartPredicateData,
              let rules = try? SmartCollectionPredicate.decodeRuleSet(data),
              SmartCollectionPredicate.canCompileRuleSet(rules) else { return nil }
        let store = store
        return { id in store.item(for: id).map(rules.matches) ?? false }
    }

    @ViewBuilder
    private func list(_ ids: [UUID]) -> some View {
        if let selection {
            List(selection: selection) {
                notSavedBanner
                ForEach(ids, id: \.self) { id in
                    row(id).tag(id)
                }
            }
        } else {
            List {
                notSavedBanner
                ForEach(ids, id: \.self) { id in
                    NavigationLink(value: ClipRoute(id: id)) { row(id) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ id: UUID) -> some View {
        if let item = store.item(for: id) {
            ClipRow(item: item)
                .contextMenu { ClipMenuItems(item: item, collections: collections) }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await appState.delete([id]) }
                    }
                }
                .swipeActions(edge: .leading) {
                    Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                        Task { await appState.togglePin(id) }
                    }
                    .tint(.orange)
                }
        }
    }

    @ViewBuilder
    private var notSavedBanner: some View {
        if !appState.storeIsOnDisk {
            Label(
                "Nothing is saved this session: the history could not be opened on disk.",
                systemImage: "bolt.slash"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func emptyState(isEmpty: Bool) -> some View {
        if isEmpty {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            } else if store.items.isEmpty {
                ContentUnavailableView(
                    "No Clips Yet",
                    systemImage: "doc.on.clipboard",
                    description: Text("Use Paste to keep what you copied, or write a new note.")
                )
            } else {
                ContentUnavailableView(
                    "Nothing Here",
                    systemImage: scope.symbolName,
                    description: Text(emptyScopeText)
                )
            }
        }
    }

    private var emptyScopeText: String {
        switch scope {
        case .pinned: String(localized: "Pin a clip to keep it here for good.")
        case .collection: String(localized: "Move a clip here from its menu.")
        case .all, .kind: String(localized: "No clip of this kind yet.")
        }
    }

    @ToolbarContentBuilder
    private var captureToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            PasteButton(supportedContentTypes: ItemProviderCapture.acceptedTypes) { providers in
                Task { await appState.add(from: providers) }
            }
            .labelStyle(.iconOnly)
            Button("New Note", systemImage: "square.and.pencil") { isComposing = true }
                .accessibilityIdentifier(MobileAccessibilityID.newNoteButton)
        }
    }
}
