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
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .focused($isEditing)
                    .padding(.horizontal, 12)
                if MobileSnippetPlaceholders.suggestsSnippet(for: text) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            Text("Placeholders like {{date}} only expand in snippets.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            editAsSnippetButton
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Placeholders like {{date}} only expand in snippets.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            editAsSnippetButton
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("New Snippet\u{2026}", systemImage: "curlybraces") {
                        library.switchFromComposeToSnippet()
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

    private var editAsSnippetButton: some View {
        Button("Edit as Snippet\u{2026}") {
            library.switchFromComposeToSnippet(initialText: text)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: TouchTarget.minimum)
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
