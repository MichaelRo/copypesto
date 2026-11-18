// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Title, note and tags edited where they are shown. A change is saved through `ClipEditor` (sealed, undoable, reported
/// if it fails) when a field is submitted, loses focus or the detail closes, and only when the text really changed.
struct ClipDetailFields: View {
    let item: ClipboardItem
    @Environment(MobileAppState.self) private var appState
    @State private var draft: ClipDetailsDraft
    @State private var baseline: ClipDetailsDraft
    @FocusState private var focused: ClipDetailsDraft.Field?

    init(item: ClipboardItem) {
        self.item = item
        let stored = ClipDetailsDraft(title: item.customTitle, note: item.userNote, tags: item.tags)
        _draft = State(initialValue: stored)
        _baseline = State(initialValue: stored)
    }

    private var stored: ClipDetailsDraft {
        ClipDetailsDraft(title: item.customTitle, note: item.userNote, tags: item.tags)
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
        .onChange(of: focused) { _, _ in
            save()
            draft.reconcile(stored: stored, baseline: &baseline, editing: focused)
        }
        .onChange(of: stored) { _, latest in draft.reconcile(stored: latest, baseline: &baseline, editing: focused) }
        .onDisappear(perform: save)
    }

    private func save() {
        let touched = draft.touched(since: baseline)
        guard !touched.isEmpty, let context = item.modelContext else { return }
        let applied = draft
        appState.clipEditor(context: context).edit(item) { clip in
            if touched.contains(.title) { clip.customTitle = applied.cleanTitle }
            if touched.contains(.note) { clip.userNote = applied.cleanNote }
            if touched.contains(.tags) { clip.tags = applied.cleanTags }
        }
        baseline.didSave(touched, from: applied)
    }
}
