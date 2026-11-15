// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The Edit Text window's content: the clip's whole text, Save (⌘Return or ⌘S) and Cancel (Esc). While the contents are
/// covered (a screen share, Hide Clip Contents) the text is covered too and the draft waits (ADR 0050).
struct TextEditView: View {
    @Bindable var model: TextEditModel
    @Environment(AppState.self) private var appState
    @AppStorage(Setting.screenSharingPrivacy) private var screenSharingPrivacy: Bool
    @FocusState private var editorFocused: Bool

    private var isCovered: Bool {
        appState.isContentCovered(screenSharingPrivacy: screenSharingPrivacy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            editor
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .pestoCaption()
                    .accessibilityIdentifier(AccessibilityID.textEditMessage)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AccessibilityID.textEditCancelButton)
                Button("Save") { Task { await model.commit() } }
                    .buttonStyle(.pestoProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canSave || isCovered)
                    .accessibilityIdentifier(AccessibilityID.textEditSaveButton)
            }
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 220)
        .background {
            Button("Save") { Task { await model.commit() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canSave || isCovered)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            editorFocused = true
        }
    }

    @ViewBuilder
    private var editor: some View {
        if isCovered {
            Label("Hidden while clip contents are covered", systemImage: "eye.slash")
                .pestoCaption()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        } else {
            TextEditor(text: $model.draft)
                .font(model.isMonospaced ? .body.monospaced() : .body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                .focused($editorFocused)
                .accessibilityLabel("Clip text")
                .accessibilityIdentifier(AccessibilityID.textEditor)
        }
    }
}
