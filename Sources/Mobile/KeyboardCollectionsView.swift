// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// Which collections the keyboard shows as chips and AutoFill lists, in the person's order (ADR 0062). Recent, Pinned
/// and Snippets are always there; this configures collections shown after them.
struct KeyboardCollectionsView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.editMode) private var editMode
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @AppStorage(Setting.keyboardCollections) private var stored: String
    @AppStorage(Setting.hiddenMobileCollections) private var hiddenCollections: String

    private var parsedOptions: QuickInsertSelection.Options {
        QuickInsertSelection.Options(
            storedCollections: stored,
            hiddenCollectionIDs: HiddenCollections.ids(from: hiddenCollections),
            returnsAfterInsert: true
        )
    }

    private var isAllMode: Bool {
        parsedOptions.collectionMode == .all
    }

    private var chosen: [Pinboard] {
        parsedOptions.resolvedCollections(from: collections)
    }

    private var others: [Pinboard] {
        let picked = Set(chosen.map(\.id))
        let hidden = parsedOptions.hiddenCollectionIDs
        return collections.filter {
            !picked.contains($0.id) && !$0.isSnippetsSmartCollection && !hidden.contains($0.id)
        }
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
            if !isAllMode, !others.isEmpty {
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
            if !isAllMode {
                Section {
                    Button("Reset to All Collections") {
                        editMode?.wrappedValue = .inactive
                        stored = QuickInsertPolicy.allCollectionsToken
                        appState.writeQuickInsert()
                    }
                } footer: {
                    Text("New collections appear automatically until you customize this list.")
                }
            }
        }
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: chosen.isEmpty) { _, empty in
            if empty { editMode?.wrappedValue = .inactive }
        }
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
