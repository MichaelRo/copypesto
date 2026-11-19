// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
            .clipResultSheets(.library)
            .sheet(isPresented: $library.showsSettings, onDismiss: showWelcomeIfAsked) { SettingsSheet() }
            .sheet(isPresented: $library.isComposing) { NewNoteView() }
            .sheet(item: $library.sharing) { share in
                ShareSheet(items: share.items, files: share.files).presentationDetents([.medium, .large])
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
            .sheet(isPresented: approvalBinding) {
                if let sync = appState.sync, let pending = sync.pendingJoin {
                    SyncApproveView(sync: sync, pending: pending)
                }
            }
            .sheet(isPresented: syncFlowBinding) {
                if let sync = appState.sync { SyncFlowSheet(sync: sync) }
            }
            .fileImporter(isPresented: $library.picksSyncFolder, allowedContentTypes: [.folder]) { result in
                if case let .success(url) = result { appState.sync?.useFolder(url) }
            }
            .task(id: appState.sync?.isEnabled ?? false) { await watchForJoinRequests() }
    }

    private func showWelcomeIfAsked() {
        if appState.takeWelcomeAgainRequest() { appState.showWelcomeAgain() }
    }

    /// Turn On Sync from the welcome opens the same flow as Settings > Sync, over the library. While Settings is up
    /// its own Sync screen presents the flow.
    private var syncFlowBinding: Binding<Bool> {
        Binding(
            get: { appState.sync.map { $0.flow != .idle } == true && !library.showsSettings },
            set: { if !$0 { appState.sync?.cancelFlow() } }
        )
    }

    /// A request from another device appears in the sync folder; the library looks for it while sync is on, as the
    /// Sync screen does while it is open.
    private func watchForJoinRequests() async {
        guard let sync = appState.sync, sync.isEnabled else { return }
        while !Task.isCancelled {
            if !library.showsSettings { sync.refresh() }
            try? await Task.sleep(for: SyncApprovalPresentation.pollInterval)
        }
    }

    private var anotherSheetIsUp: Bool {
        library.showsSettings || library.isComposing || library.isNamingCollection || library.editingCollection != nil
            || library.sharing != nil || appState.pendingFill != nil || appState.decodedJWT != nil
            || appState.showsAI
            || library.openClipID != nil && sizeClass == .compact
    }

    private var approvalBinding: Binding<Bool> {
        Binding(
            get: {
                SyncApprovalPresentation.presentsOverLibrary(
                    hasPendingJoin: appState.sync?.pendingJoin != nil, flowIsIdle: appState.sync?.flow == .idle,
                    anotherSheetIsUp: anotherSheetIsUp
                )
            },
            set: { _ in }
        )
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
