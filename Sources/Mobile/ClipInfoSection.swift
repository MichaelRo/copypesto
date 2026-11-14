// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The title, note and tags the person gave the clip, with the way to change them.
struct ClipInfoSection: View {
    let item: ClipboardItem
    @Binding var isEditing: Bool

    var body: some View {
        Section("Title, note and tags") {
            if let title = item.customTitle, !title.isEmpty {
                LabeledContent("Title", value: title)
            }
            if let note = item.userNote, !note.isEmpty {
                Text(note).textSelection(.enabled)
            }
            if !item.tags.isEmpty {
                Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                    .foregroundStyle(.secondary)
            }
            Button("Edit Details", systemImage: "pencil") { isEditing = true }
        }
    }
}
