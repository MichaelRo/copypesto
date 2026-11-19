// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// Which collections the keyboard shows as chips and AutoFill lists, in the person's order (ADR 0062). Recent, Pinned
/// and Snippets are always there; this adds collections after them.
struct KeyboardCollectionsView: View {
    @Environment(MobileAppState.self) private var appState
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @AppStorage(Setting.keyboardCollections) private var stored: String

    private var chosenIDs: [UUID] {
        QuickInsertSelection.Options(storedCollections: stored, returnsAfterInsert: true).collectionIDs
    }

    private var chosen: [Pinboard] {
        let byID = Dictionary(collections.map { ($0.id, $0) }) { first, _ in first }
        return chosenIDs.compactMap { byID[$0] }
    }

    private var others: [Pinboard] {
        let picked = Set(chosenIDs)
        return collections.filter { !picked.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                ForEach(chosen) { collection in
                    label(collection)
                }
                .onMove { from, to in
                    var ids = chosen.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    save(ids)
                }
                .onDelete { offsets in
                    var ids = chosen.map(\.id)
                    ids.remove(atOffsets: offsets)
                    save(ids)
                }
            } header: {
                Text("In the keyboard")
            } footer: {
                Text("After Recent, Pinned and Snippets, in this order. Drag to reorder, swipe to remove.")
            }
            if !others.isEmpty {
                Section("Add") {
                    ForEach(others) { collection in
                        Button {
                            save(chosen.map(\.id) + [collection.id])
                        } label: {
                            label(collection)
                        }
                        .disabled(chosen.count >= QuickInsertPolicy.maxCollections)
                    }
                }
            }
        }
        .navigationTitle("Collections")
        .toolbar { EditButton() }
    }

    private func label(_ collection: Pinboard) -> some View {
        Label(collection.name, systemImage: collection.symbolName)
            .foregroundStyle(.primary)
    }

    private func save(_ ids: [UUID]) {
        stored = QuickInsertSelection.Options.stored(ids)
        appState.writeQuickInsert()
    }
}
