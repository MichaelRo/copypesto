// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Title, note and tags edited where they are shown. A change is saved through `ClipEditor` (sealed, undoable, reported
/// if it fails) when a field is submitted, loses focus or the detail closes, and only when the text really changed.
struct ClipDetailFields: View {
    let item: ClipboardItem
    @Environment(MobileAppState.self) private var appState
    @State private var draft: ClipDetailsDraft
    @FocusState private var focused: Field?

    private enum Field {
        case title, note, tags
    }

    init(item: ClipboardItem) {
        self.item = item
        _draft = State(initialValue: ClipDetailsDraft(title: item.customTitle, note: item.userNote, tags: item.tags))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $draft.title)
                .font(.headline)
                .focused($focused, equals: .title)
            TextField("Note", text: $draft.note, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused, equals: .note)
            TextField("Tags, separated by commas", text: $draft.tags)
                .textInputAutocapitalization(.never)
                .font(.subheadline)
                .focused($focused, equals: .tags)
        }
        .textFieldStyle(.plain)
        .padding(14)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12, style: .continuous))
        .onSubmit(save)
        .onChange(of: focused) { _, _ in save() }
        .onDisappear(perform: save)
    }

    private func save() {
        guard draft.differs(title: item.customTitle, note: item.userNote, tags: item.tags),
              let context = item.modelContext else { return }
        let applied = draft
        appState.clipEditor(context: context).edit(item) { clip in
            clip.customTitle = applied.cleanTitle
            clip.userNote = applied.cleanNote
            clip.tags = applied.cleanTags
        }
    }
}
