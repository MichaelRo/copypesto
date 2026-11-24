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
                if chosen.isEmpty {
                    Text("No extra collections added")
                        .foregroundStyle(.secondary)
                } else {
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
                }
            } header: {
                Text("Shown in Keyboard & AutoFill")
            } footer: {
                Text(
                    "After All, Pinned, and Snippets, in this order. Snippets are pinned clips with " +
                        "placeholders like {{date}}. Drag to reorder, swipe to remove."
                )
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { collection in
                        Button {
                            save(chosen.map(\.id) + [collection.id])
                        } label: {
                            label(collection)
                        }
                        .disabled(chosen.count >= QuickInsertPolicy.maxCollections)
                    }
                } header: {
                    Text("Add")
                } footer: {
                    if chosen.count >= QuickInsertPolicy.maxCollections {
                        Text("Collection limit reached.")
                    }
                }
            }
        }
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !chosen.isEmpty {
                EditButton()
            }
        }
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
