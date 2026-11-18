// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A plain-text note the person writes; it is saved as a clip through ingest like anything copied.
struct NewNoteView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
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
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(ClipCapture.text(text) == nil)
                    }
                }
                .onAppear { isEditing = true }
        }
    }

    private func save() {
        let capture = ClipCapture.text(text)?.with(captureMethod: .note)
        Task {
            if await appState.add(capture) { dismiss() }
        }
    }
}
