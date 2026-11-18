// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// Everything the library page presents over itself, once for both layouts: Settings, a new note, a new or edited
/// collection, the delete confirmation from the keyboard, and the share sheet a card's menu opens.
struct LibraryPresentations: ViewModifier {
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]

    func body(content: Content) -> some View {
        @Bindable var library = library
        content
            .sheet(item: fillBinding) { request in
                SnippetFillSheet(request: request).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $library.showsSettings) { SettingsSheet() }
            .sheet(isPresented: $library.isComposing) { NewNoteView() }
            .sheet(item: $library.sharing) { share in
                ShareSheet(items: share.items).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $library.isNamingCollection) {
                CollectionEditorView(board: nil).presentationDetents([.medium, .large])
            }
            .sheet(item: $library.editingCollection) { board in
                CollectionEditorView(board: board).presentationDetents([.medium, .large])
            }
            .confirmationDialog("Delete this clip?", isPresented: deleteBinding, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deletePending() }
            }
            .onChange(of: collections.map(\.id)) { _, ids in library.filter.forget(collections: ids) }
    }

    /// A clip's detail sheet presents its own fill sheet, since a sheet cannot present over a sheet from below.
    private var fillBinding: Binding<SnippetFillRequest?> {
        Binding(
            get: { library.openClipID != nil && sizeClass == .compact ? nil : appState.pendingFill },
            set: { appState.pendingFill = $0 }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { library.pendingDelete != nil }, set: { if !$0 { library.pendingDelete = nil } })
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
