// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Title, note and tags, saved through `ClipEditor` so the change is sealed, undoable and reported if it fails.
struct ClipEditView: View {
    let item: ClipboardItem
    @Environment(MobileAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ClipDetailsDraft

    init(item: ClipboardItem) {
        self.item = item
        _draft = State(initialValue: ClipDetailsDraft(title: item.customTitle, note: item.userNote, tags: item.tags))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $draft.title)
                }
                Section("Note") {
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    TextField("Tags", text: $draft.tags)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Separate tags with commas.")
                }
            }
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        guard let context = item.modelContext else { return dismiss() }
        let applied = draft
        appState.clipEditor(context: context).edit(item) { clip in
            clip.customTitle = applied.cleanTitle
            clip.userNote = applied.cleanNote
            clip.tags = applied.cleanTags
        }
        dismiss()
    }
}
