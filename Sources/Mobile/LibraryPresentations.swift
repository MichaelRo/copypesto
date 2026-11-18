// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// Everything the library page presents over itself, once for both layouts: Settings, a new note, naming and renaming a
/// collection, the delete confirmation from the keyboard, and the share sheet a card's menu opens.
struct LibraryPresentations: ViewModifier {
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var newName = ""

    func body(content: Content) -> some View {
        @Bindable var library = library
        content
            .sheet(isPresented: $library.showsSettings) { SettingsSheet() }
            .sheet(isPresented: $library.isComposing) { NewNoteView() }
            .sheet(item: $library.sharing) { share in
                ShareSheet(items: share.items).presentationDetents([.medium, .large])
            }
            .alert("New Collection", isPresented: $library.isNamingCollection) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Add") { addCollection() }
            }
            .alert("Rename Collection", isPresented: renamingBinding) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Rename") { rename() }
            }
            .confirmationDialog("Delete this clip?", isPresented: deleteBinding, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deletePending() }
            }
            .onChange(of: collections.map(\.id)) { _, ids in library.filter.forget(collections: ids) }
            .onChange(of: library.renaming) { _, board in newName = board?.name ?? "" }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { library.renaming != nil }, set: { if !$0 { library.renaming = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { library.pendingDelete != nil }, set: { if !$0 { library.pendingDelete = nil } })
    }

    private func addCollection() {
        if let board = appState.addCollection(named: newName, existing: collections) {
            library.filter.choose(.collection(board.id))
        }
        newName = ""
    }

    private func rename() {
        if let board = library.renaming {
            appState.renameCollection(board, to: newName, existing: collections)
        }
        library.renaming = nil
        newName = ""
    }

    private func deletePending() {
        guard let id = library.pendingDelete else { return }
        library.pendingDelete = nil
        if library.openClipID == id { library.openClipID = nil }
        Task { await appState.delete([id]) }
    }
}

extension View {
    func libraryPresentations() -> some View {
        modifier(LibraryPresentations())
    }
}
