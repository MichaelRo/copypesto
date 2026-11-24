// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// Floating bulk-action bar shown while multi-select mode is active in the iOS library.
struct MobileSelectionBar: View {
    let collections: [Pinboard]
    let allVisibleIDs: [UUID]
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @State private var isConfirmingBulkDelete = false

    private var count: Int {
        library.selectedClipIDs.count
    }

    private func orderedSelectedItems(in store: HistoryStore?) -> [ClipboardItem] {
        guard let store else { return [] }
        return allVisibleIDs.compactMap { library.selectedClipIDs.contains($0) ? store.item(for: $0) : nil }
    }

    var body: some View {
        let selected = orderedSelectedItems(in: appState.historyStore)
        let textual = selected.filter { $0.type == .text || $0.type == .code }
        let anyUnpinned = selected.contains { !$0.isPinned }
        let selectAllButton = Button(
            library.selectedClipIDs.count == allVisibleIDs.count && !allVisibleIDs.isEmpty
                ? "Deselect" : "Select All"
        ) {
            if library.selectedClipIDs.count == allVisibleIDs.count {
                library.selectedClipIDs = []
            } else {
                library.selectAll(allVisibleIDs)
            }
        }
        .font(.subheadline)
        .disabled(allVisibleIDs.isEmpty)

        let countText = Text("\(count) clips selected")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                selectAllButton
                countText
                Spacer(minLength: 4)
                actionButtons(selected: selected, textual: textual, anyUnpinned: anyUnpinned)
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    selectAllButton
                    Spacer(minLength: 4)
                    countText
                }
                HStack(spacing: 12) {
                    actionButtons(selected: selected, textual: textual, anyUnpinned: anyUnpinned)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .mobileGlassChrome(in: .capsule, interactive: true)
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .confirmationDialog(
            String(localized: "Delete \(count) clips?"),
            isPresented: $isConfirmingBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected() }
        }
    }

    @ViewBuilder
    private func actionButtons(
        selected: [ClipboardItem], textual: [ClipboardItem], anyUnpinned: Bool
    )
    -> some View {
        if textual.count >= 2 {
            Button {
                if appState.copyJoined(textual) {
                    library.endSelection()
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
            }
            .accessibilityLabel(String(localized: "Copy All"))
            .accessibilityIdentifier(MobileAccessibilityID.copyAllButton)
        }

        let plainCollections = collections.filter { !$0.isSmart }
        if !plainCollections.isEmpty {
            Menu {
                ForEach(plainCollections, id: \.id) { board in
                    Button {
                        appState.moveToCollection(selected, collectionID: board.id)
                        library.endSelection()
                    } label: {
                        Label(board.name, systemImage: board.symbolName)
                    }
                }
                Divider()
                Button("Remove from Collection") {
                    appState.moveToCollection(selected, collectionID: nil)
                    library.endSelection()
                }
            } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
            }
            .disabled(library.selectedClipIDs.isEmpty)
            .accessibilityLabel(String(localized: "Move to Collection"))
        }

        Button {
            let ids = selected.map(\.id)
            let pin = anyUnpinned
            Task {
                await appState.setPinned(ids, pinned: pin)
                library.endSelection()
            }
        } label: {
            Image(systemName: anyUnpinned ? "pin" : "pin.slash")
                .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
        }
        .disabled(library.selectedClipIDs.isEmpty)
        .accessibilityLabel(String(localized: anyUnpinned ? "Pin" : "Unpin"))

        Button(role: .destructive) {
            if count > 1 {
                isConfirmingBulkDelete = true
            } else {
                deleteSelected()
            }
        } label: {
            Image(systemName: "trash")
                .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
        }
        .disabled(library.selectedClipIDs.isEmpty)
        .accessibilityLabel(String(localized: "Delete"))
    }

    private func deleteSelected() {
        let ids = Array(library.selectedClipIDs)
        library.endSelection()
        Task { await appState.delete(ids) }
    }
}
