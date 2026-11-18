// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The clip's text as an editor, opened by Edit Text in the detail and closed by Save or Cancel, so that outside it a
/// tap on the text still selects. Save goes through `MobileAppState.editText` (sealed, judged again, undoable).
struct ClipTextEditor: View {
    let item: ClipboardItem
    let onClose: () -> Void

    @Environment(MobileAppState.self) private var appState
    @Binding var draft: String
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $draft)
                .font(item.type == .code || item.type == .color ? .body.monospaced() : .body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12, style: .continuous))
                .focused($isFocused)
                .accessibilityIdentifier(MobileAccessibilityID.textEditor)
            if let notice = appState.notice, notice.isProblem {
                Label(notice.text, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel", role: .cancel, action: onClose)
                    .accessibilityIdentifier(MobileAccessibilityID.cancelTextEditButton)
                Spacer()
                Button("Save") { save() }
                    .bold()
                    .disabled(isSaving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier(MobileAccessibilityID.saveTextButton)
            }
        }
        .onAppear { isFocused = true }
    }

    private func save() {
        isSaving = true
        let text = draft
        Task {
            let saved = await appState.editText(of: item, to: text)
            isSaving = false
            if saved { onClose() }
        }
    }
}
