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

    private var selectedItems: [ClipboardItem] {
        guard let store = appState.historyStore else { return [] }
        return library.selectedClipIDs.compactMap { store.item(for: $0) }
    }

    private var anyUnpinned: Bool {
        selectedItems.contains { !$0.isPinned }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(library.selectedClipIDs.count == allVisibleIDs.count && !allVisibleIDs
                .isEmpty ? "Deselect" : "Select All")
            {
                if library.selectedClipIDs.count == allVisibleIDs.count {
                    library.selectedClipIDs = []
                } else {
                    library.selectAll(allVisibleIDs)
                }
            }
            .font(.subheadline)
            .disabled(allVisibleIDs.isEmpty)

            Text("\(count) clips selected")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 4)

            let plainCollections = collections.filter { !$0.isSmart }
            if !plainCollections.isEmpty {
                Menu {
                    ForEach(plainCollections, id: \.id) { board in
                        Button {
                            appState.moveToCollection(selectedItems, collectionID: board.id)
                            library.endSelection()
                        } label: {
                            Label(board.name, systemImage: board.symbolName)
                        }
                    }
                    Divider()
                    Button("Remove from Collection") {
                        appState.moveToCollection(selectedItems, collectionID: nil)
                        library.endSelection()
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .frame(minWidth: 36, minHeight: 36)
                }
                .disabled(library.selectedClipIDs.isEmpty)
                .accessibilityLabel(String(localized: "Move to Collection"))
            }

            Button {
                let ids = Array(library.selectedClipIDs)
                let pin = anyUnpinned
                Task {
                    await appState.setPinned(ids, pinned: pin)
                    library.endSelection()
                }
            } label: {
                Image(systemName: anyUnpinned ? "pin" : "pin.slash")
                    .frame(minWidth: 36, minHeight: 36)
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
                    .frame(minWidth: 36, minHeight: 36)
            }
            .disabled(library.selectedClipIDs.isEmpty)
            .accessibilityLabel(String(localized: "Delete"))
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

    private func deleteSelected() {
        let ids = Array(library.selectedClipIDs)
        library.endSelection()
        Task { await appState.delete(ids) }
    }
}
