// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The Clip window's left pane (ADRs 0050, 0071): the title, then the clip's whole text to edit, with Revert and Save
/// (⌘Return or ⌘S) while it is changed and Close (Esc). A clip whose text is not editable (a picture, a file, a hidden
/// secret) shows as its hover card does. While the contents are covered (a screen share, Hide Clip Contents) the
/// content is covered too and the draft waits.
struct TextEditView: View {
    @Bindable var model: TextEditModel
    let item: ClipboardItem?
    let editor: ClipEditor?
    var showsPreview = true
    var showsPersonalDetails = true
    @Environment(AppState.self) private var appState
    @AppStorage(Setting.screenSharingPrivacy) private var screenSharingPrivacy: Bool
    @FocusState private var editorFocused: Bool
    @FocusState private var titleFocused: Bool
    @State private var title = ""
    @State private var titleBaseline = ""

    private var isCovered: Bool {
        appState.isContentCovered(screenSharingPrivacy: screenSharingPrivacy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item != nil, showsPersonalDetails { titleField }
            content
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .pestoCaption()
                    .accessibilityIdentifier(AccessibilityID.textEditMessage)
            }
            HStack {
                Spacer()
                if model.hasUnsavedChanges {
                    Button("Revert") { model.revert() }
                        .accessibilityIdentifier(AccessibilityID.clipInspectorRevert)
                }
                Button(model.hasUnsavedChanges ? "Cancel" : "Close") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AccessibilityID.textEditCancelButton)
                if model.isEditable {
                    Button("Save") { Task { await model.commit() } }
                        .buttonStyle(.pestoProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!model.canSave || isCovered)
                        .accessibilityIdentifier(AccessibilityID.textEditSaveButton)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 340, minHeight: 220)
        .background {
            Button("Save") { Task { await model.commit() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canSave || isCovered)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            title = item?.customTitle ?? ""
            titleBaseline = title
        }
        .onChange(of: item?.customTitle) { _, stored in
            // Renamed elsewhere (the card, sync) while untouched here: show the new title.
            guard !titleFocused, !ClipDetailsEdit.personChanged(title, from: titleBaseline) else { return }
            title = stored ?? ""
            titleBaseline = title
        }
        .onChange(of: titleFocused) { _, isFocused in if !isFocused { saveTitle() } }
        .onDisappear(perform: saveTitle)
        .task {
            guard model.isEditable else { return }
            try? await Task.sleep(for: .milliseconds(80))
            editorFocused = true
        }
    }

    private var titleField: some View {
        TextField("Title", text: $title, prompt: Text("Add a title"))
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .focused($titleFocused)
            .onSubmit(saveTitle)
            .accessibilityIdentifier(AccessibilityID.clipInspectorTitle)
    }

    /// Saved only when the person changed it, the clip still exists and the history is not locked (the window can
    /// close after a delete or the lock, which has already emptied Undo).
    private func saveTitle() {
        guard let item, let editor, showsPersonalDetails, !item.isDeleted, item.modelContext != nil,
              !appState.isHistoryLockedNow(), ClipDetailsEdit.personChanged(title, from: titleBaseline) else { return }
        let saved = ClipDetailsEdit.title(title)
        titleBaseline = title
        guard saved != item.customTitle else { return }
        editor.edit(item) { $0.customTitle = saved }
    }

    @ViewBuilder
    private var content: some View {
        if isCovered {
            Label("Hidden while clip contents are covered", systemImage: "eye.slash")
                .pestoCaption()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        } else if !model.isEditable, !showsPreview {
            Label("Hidden on the shelf. Show reveals it.", systemImage: "lock")
                .pestoCaption()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        } else if !model.isEditable {
            ScrollView {
                if let item { CardDetailPopover(item: item).frame(maxWidth: .infinity) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
