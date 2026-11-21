// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// A plain-text note the person writes; it is saved as a clip through ingest like anything copied.
struct NewNoteView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var text = ""
    @State private var isConfirmingDiscard = false
    @FocusState private var isEditing: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isEditing)
                .padding(.horizontal, 12)
                .navigationTitle("New Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button("New Snippet\u{2026}", systemImage: "curlybraces") {
                            dismiss()
                            library.beginNewSnippet()
                        }
                        .accessibilityIdentifier(MobileAccessibilityID.newSnippetButton)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(ClipCapture.text(text) == nil)
                    }
                }
                .onAppear { isEditing = true }
                .confirmationDialog(
                    "Discard this note?",
                    isPresented: $isConfirmingDiscard,
                    titleVisibility: .visible
                ) {
                    Button("Discard", role: .destructive) { dismiss() }
                    Button("Keep Editing", role: .cancel) {}
                }
        }
        .interactiveDismissDisabled(NoteDraft.needsDiscardConfirmation(text))
    }

    private func cancel() {
        if NoteDraft.needsDiscardConfirmation(text) {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        let capture = ClipCapture.text(text)?.with(captureMethod: .note)
        let destination = library.targetCollectionID(in: collections)
        Task {
            if await appState.add(capture, into: destination) { dismiss() }
        }
    }
}
