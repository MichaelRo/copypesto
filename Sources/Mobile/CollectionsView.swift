// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The compact Collections tab: every collection, and a way to add one.
struct CollectionsView: View {
    let store: HistoryStore
    @Environment(MobileAppState.self) private var appState
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var isNaming = false

    var body: some View {
        List {
            ForEach(collections, id: \.id) { board in
                NavigationLink(value: CollectionRoute(id: board.id, name: board.name)) {
                    CollectionLabel(board: board)
                }
            }
        }
        .overlay {
            if collections.isEmpty {
                ContentUnavailableView(
                    "No Collections",
                    systemImage: "folder",
                    description: Text("A collection keeps related clips together.")
                )
            }
        }
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Collection", systemImage: "folder.badge.plus") { isNaming = true }
            }
        }
        .newCollectionAlert(isPresented: $isNaming, existing: collections)
    }
}

struct CollectionLabel: View {
    let board: Pinboard

    var body: some View {
        Label {
            Text(board.name)
        } icon: {
            Image(systemName: board.isSmart ? "sparkles" : board.symbolName)
                .foregroundStyle(Color(hex: board.colorHex) ?? .secondary)
        }
    }
}

extension View {
    func newCollectionAlert(isPresented: Binding<Bool>, existing: [Pinboard]) -> some View {
        modifier(NewCollectionAlert(isPresented: isPresented, existing: existing))
    }
}

private struct NewCollectionAlert: ViewModifier {
    @Binding var isPresented: Bool
    let existing: [Pinboard]
    @Environment(MobileAppState.self) private var appState
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("New Collection", isPresented: $isPresented) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { name = "" }
            Button("Add") {
                _ = appState.addCollection(named: name, existing: existing)
                name = ""
            }
        }
    }
}
