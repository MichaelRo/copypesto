// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The Clip Inspector's right pane: the note, the tags, the collection, Pinned and the facts. A field is saved when it
/// loses focus or Return is pressed, so closing the window never loses a typed note.
struct ClipDetailsPane: View {
    let item: ClipboardItem
    let editor: ClipEditor
    let collections: [Pinboard]
    @Environment(AppState.self) private var appState
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var note = ""
    @State private var newTag = ""
    @FocusState private var focused: Field?

    private enum Field {
        case note, tag
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                noteSection
                tagSection
                collectionSection
                factsSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { note = item.userNote ?? "" }
        .onChange(of: focused) { old, _ in
            if old == .note { saveNote() }
            if old == .tag { addTags() }
        }
        .onDisappear {
            saveNote()
            addTags()
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Note")
            TextField("Add a note", text: $note, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .note)
                .accessibilityIdentifier(AccessibilityID.clipInspectorNote)
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Tags")
            if !item.tags.isEmpty {
                PlaceholderFlowLayout(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
            }
            TextField("Add a tag", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .tag)
                .onSubmit(addTags)
                .accessibilityIdentifier(AccessibilityID.clipInspectorTagField)
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text("@\(tag)")
            Button {
                editor.edit(item) { $0.tags = ClipDetailsEdit.removing(tag, from: $0.tags) }
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Remove tag \(tag)"))
        }
        .pestoCaption()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.6), in: .capsule)
    }

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Collection")
            Picker("Collection", selection: Binding(
                get: { item.collectionID },
                set: { id in editor.edit(item) { $0.collectionID = id } }
            )) {
                Text("None").tag(UUID?.none)
                ForEach(collections) { collection in
                    Label(collection.name, systemImage: collection.symbolName).tag(UUID?.some(collection.id))
                }
            }
            .labelsHidden()
            .accessibilityIdentifier(AccessibilityID.clipInspectorCollection)
            Toggle("Pinned", isOn: Binding(get: { item.isPinned }, set: { _ in togglePin() }))
                .accessibilityIdentifier(AccessibilityID.clipInspectorPinned)
        }
    }

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading("Details")
            if let app = item.sourceAppName, !app.isEmpty {
                Text("From \(app)")
            }
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                Text(DetailFactsText.text(for: fact, now: .now, calendar: calendar, locale: locale))
            }
        }
        .pestoCaption()
        .textSelection(.enabled)
    }

    private var facts: [DetailFact] {
        let collectionName = collections.first { $0.id == item.collectionID }?.name
        return DetailFactsText.facts(
            for: item, collectionName: collectionName, shownText: item.gridPreview, wasCut: false
        )
        .filter { if case .collection = $0 { false } else { true } }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .pestoQuiet()
    }

    private func saveNote() {
        let saved = ClipDetailsEdit.note(note)
        guard saved != item.userNote else { return }
        editor.edit(item) { $0.userNote = saved }
    }

    private func addTags() {
        let updated = ClipDetailsEdit.adding(newTag, to: item.tags)
        newTag = ""
        guard updated != item.tags else { return }
        editor.edit(item) { $0.tags = updated }
    }

    private func togglePin() {
        let id = item.id
        Task {
            await appState.attempt("Couldn\u{2019}t pin the clip") {
                _ = try await appState.storageService?.togglePinned(id: id)
            }
        }
    }
}
