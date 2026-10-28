// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// Settings → Snippets: create and manage pinned items with `{{placeholder}}` syntax.
///
/// Snippets are regular `ClipboardItem` rows (isPinned: true) whose previewText contains
/// at least one `{{...}}` token. They appear in the main grid with a `curlybraces` badge
/// and are expanded at paste time by `TemplateExpander`.
struct SnippetsView: View {
    @Environment(\.pestoAccent) private var accent
    @Query(filter: #Predicate<ClipboardItem> { $0.isPinned }) private var pinnedItems: [ClipboardItem]
    @Query(
        filter: #Predicate<ClipboardItem> { !$0.isPinned && $0.pasteCount >= 3 },
        sort: [SortDescriptor(\ClipboardItem.pasteCount, order: .reverse)]
    ) private var pastedOften: [ClipboardItem]
    @AppStorage(Setting.dismissedSnippetSuggestions) private var dismissedRaw: String
    @AppStorage(Setting.rememberFillIns) private var remembersFillIns: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState

    @State private var editor: SnippetEditorDraft?
    @State private var pendingDelete: ClipboardItem?
    let addRequest: Int

    private var dismissed: Set<String> {
        Set(dismissedRaw.split(separator: "\n").map(String.init))
    }

    /// Starters that are not already among the snippets (by text) and have not been dismissed.
    private var starters: [SnippetStarter] {
        let have = Set(snippets.map { $0.displayPreviewText.trimmingCharacters(in: .whitespacesAndNewlines) })
        return SnippetStarters.all.filter { !dismissed.contains($0.id) && !have.contains($0.text) }
    }

    private var fromYourClips: [SnippetCandidate] {
        let candidates = pastedOften.prefix(50).map { item in
            SnippetCandidate(
                id: item.id, text: item.displayPreviewText, pasteCount: item.pasteCount, isPinned: item.isPinned,
                isTextual: item.typeRaw == ClipboardType.text.rawValue || item.typeRaw == ClipboardType.code.rawValue,
                isSecret: item.sensitivityRaw != nil
            )
        }
        return SnippetSuggester.suggestions(from: candidates, dismissed: Set(dismissed.compactMap(UUID.init)))
    }

    private var snippets: [ClipboardItem] {
        pinnedItems.filter(\.isTemplate)
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(SnippetDraft.placeholders, id: \.token) { placeholder in
                        HStack(spacing: 8) {
                            Keycap(symbol: placeholder.token)
                            Text(placeholder.meaning).pestoCaption()
                        }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Placeholders you can use in a snippet")
            } header: {
                Text("Placeholders")
            } footer: {
                Text(
                    "Use these inside a snippet. They are filled in when you paste it. "
                        + "\u{201C}Add Question\u{2026}\u{201D} in the editor asks one instead."
                )
                .pestoCaption()
            }

            Section {
                if let editor, editor.clipID == nil, editor.anchorID == nil { editorView(editor) }
                if snippets.isEmpty, editor == nil {
                    emptyState
                }
                ForEach(snippets) { snippet in
                    if let editor, editor.clipID == snippet.id {
                        editorView(editor)
                    } else {
                        snippetRow(snippet)
                    }
                }
                .onDelete(perform: deleteSnippets)
            } header: {
                Text("Your snippets")
            } footer: {
                if !snippets.isEmpty {
                    Text("Double-click a snippet to edit it. A shortcut such as ⌃1 pastes one in any app.")
                        .pestoCaption()
                }
            }

            if !starters.isEmpty {
                Section {
                    ForEach(starters) { starter in starterRow(starter) }
                } header: {
                    Text("Starters")
                } footer: {
                    Text("Templates to begin with. Each fills in the date or time when you paste it.").pestoCaption()
                }
            }

            if !fromYourClips.isEmpty {
                Section {
                    ForEach(fromYourClips, id: \.id) { candidate in
                        if let editor, editor.anchorID == candidate.id.uuidString {
                            editorView(editor)
                        } else {
                            clipRow(candidate)
                        }
                    }
                } header: {
                    Text("From your clips")
                } footer: {
                    Text("Text you have pasted from the shelf more than twice. Make a snippet to keep it handy.")
                        .pestoCaption()
                }
            }

            Section {
                Toggle(isOn: $remembersFillIns) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remember fill-in values")
                        Text(
                            remembersFillIns
                                ? "A snippet starts with what you typed last time. It is kept with the snippet, "
                                + "sealed like its text."
                                : "A snippet starts empty every time. What was remembered is erased."
                        )
                        .pestoCaption()
                    }
                }
                .settingsRow("Remember fill-in values")
                .onChange(of: remembersFillIns) { _, remembers in
                    guard !remembers else { return }
                    Task {
                        await appState.attempt("Couldn\u{2019}t erase the remembered values") {
                            try await appState.storageService?.forgetAllFillIns()
                        }
                    }
                }
            }

            Section {
                suggestionStatistics
            } header: {
                Text("Suggestion statistics")
            } footer: {
                Text("Kept on this Mac, from the suggestions the shelf has shown. Nothing is sent anywhere.")
                    .pestoCaption()
            }
        }
        .formStyle(.grouped)
        .onChange(of: addRequest) { editor = .new() }
        .onAppear {
            if let seedID = appState.pendingSnippetSeed {
                appState.pendingSnippetSeed = nil
                Task {
                    if let texts = await appState.storageService?.familyTexts(of: seedID),
                       let proposal = TemplateInferrer.propose(from: texts)
                    {
                        editor = .new(text: proposal.template)
                        return
                    }
                    seedFromClip(seedID)
                }
            }
        }
        .confirmationDialog(
            "Delete this snippet?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Snippet", role: .destructive) {
                if let snippet = pendingDelete { delete(snippet) }
                pendingDelete = nil
            }
            .accessibilityIdentifier(AccessibilityID.deleteSnippetConfirmButton)
        } message: {
            Text("It is removed from your history too. A backup made earlier can still bring it back.")
        }
    }

    private var suggestionStatistics: some View {
        let summary = SuggestionStats(
            ledger: SuggestionLedger(serialized: AppDefaults.store.value(for: Setting.shelfSuggestionLedger))
        ).summary
        return HStack(alignment: .top, spacing: 12) {
            Text(verbatim: summary)
                .scaledFont(size: 11.5, design: .monospaced)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy Summary") { appState.writeText(summary, protected: false) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .settingsRow("Suggestion statistics")
    }

    private func seedFromClip(_ seedID: UUID) {
        if let item = pastedOften.first(where: { $0.id == seedID }) ?? pinnedItems.first(where: { $0.id == seedID }) {
            editor = .new(text: item.displayPreviewText, anchorID: item.id.uuidString)
        } else if let item = try? modelContext
            .fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == seedID })).first
        {
            editor = .new(text: item.displayPreviewText)
        }
    }

    // MARK: - Sub-views

    private func editorView(_ draft: SnippetEditorDraft) -> some View {
        SnippetEditorView(draft: draft, freeShortcutSlot: freeShortcutSlot, onSave: save, onCancel: { editor = nil })
            .id(draft.id)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "curlybraces")
                .font(.title)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("No snippets yet").fontWeight(.medium)
            Text("Add a snippet with {{placeholders}} to expand at paste time.")
                .pestoCaption()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func starterRow(_ starter: SnippetStarter) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: starter.name)
                Text(verbatim: starter.blurb).pestoCaption()
            }
            Spacer()
            Button("Add") { addStarter(starter) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier(AccessibilityID.addSnippetStarter(starter.id))
            dismissButton(for: starter.id, name: starter.name)
        }
    }

    private func clipRow(_ candidate: SnippetCandidate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: String(candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)))
                    .lineLimit(1)
                Text("Pasted \(candidate.pasteCount) times").pestoCaption()
            }
            Spacer()
            Button("Make Snippet") { editor = .new(text: candidate.text, anchorID: candidate.id.uuidString) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            dismissButton(for: candidate.id.uuidString, name: String(candidate.text.prefix(20)))
        }
    }

    private func dismissButton(for id: String, name: String) -> some View {
        Button {
            dismissedRaw = dismissed.union([id]).sorted().joined(separator: "\n")
        } label: {
            Image(systemName: "xmark").font(.caption.weight(.semibold))
        }
        .buttonStyle(.plain)
        .pestoQuiet()
        .accessibilityLabel("Dismiss \(name)")
        .help("Do not suggest this again")
    }

    private func snippetRow(_ snippet: ClipboardItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                let text = SnippetRowText(preview: snippet.displayPreviewText, customTitle: snippet.customTitle)
                SnippetTitleLine(snippet: snippet, title: text.title)
                if !text.body.isEmpty {
                    Text(verbatim: text.body)
                        .scaledFont(size: 12, design: .monospaced)
                        .pestoCaption()
                        .lineLimit(2)
                }
                if let slot = snippet.pinnedHotkeyIndex {
                    HStack(spacing: 4) {
                        Keycap(symbol: "\u{2303}")
                        Keycap(symbol: "\(slot)")
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            Button("Edit") { edit(snippet) }
                .accessibilityIdentifier(AccessibilityID.editSnippetButton)
            Button("Delete", role: .destructive) { pendingDelete = snippet }
                .accessibilityIdentifier(AccessibilityID.deleteSnippetButton)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { edit(snippet) }
        .contextMenu {
            Button("Edit\u{2026}") { edit(snippet) }
            Button("Delete", role: .destructive) { pendingDelete = snippet }
        }
    }

    private func edit(_ snippet: ClipboardItem) {
        editor = SnippetEditorDraft(
            clipID: snippet.id, title: snippet.customTitle ?? "", text: ClipText.full(of: snippet)
        )
    }

    // MARK: - Actions

    private func save(_ draft: SnippetEditorDraft) {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SnippetDraft.evaluate(text) == .ready else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        editor = nil
        let service = storage
        Task {
            if let clipID = draft.clipID {
                _ = try? await service.updateSnippet(id: clipID, title: title.isEmpty ? nil : title, text: text)
            } else {
                let id = try? await service.addSnippet(text, title: title.isEmpty ? nil : title)
                if let id, let slot = draft.shortcutSlot {
                    await appState.attempt("Couldn\u{2019}t set the shortcut") {
                        try await service.assignFreeHotkeySlot(slot, to: id)
                    }
                }
            }
        }
    }

    private var freeShortcutSlot: Int? {
        ShelfSuggestionPolicy.freeSlot(
            assigned: Set(pinnedItems.compactMap(\.pinnedHotkeyIndex)),
            unavailable: appState.hotkeyController.unavailableSlots
        )
    }

    private func addStarter(_ starter: SnippetStarter) {
        let service = storage
        Task { _ = try? await service.addSnippet(starter.text, title: starter.name) }
    }

    /// The app's own service, which owns the undo history; a throwaway one would remember nothing.
    private var storage: StorageService {
        appState.storageService ?? StorageService(modelContainer: modelContext.container)
    }

    private func deleteSnippets(at offsets: IndexSet) {
        remove(offsets.map { snippets[$0].id })
    }

    private func delete(_ snippet: ClipboardItem) {
        remove([snippet.id])
    }

    /// Through the service, like every delete: one tombstone path, and ⌘Z can bring the snippet back.
    private func remove(_ ids: [UUID]) {
        let service = storage
        Task {
            await appState.attempt("Couldn\u{2019}t delete the snippet") {
                try await service.deleteItems(ids: ids, reason: .user)
            }
        }
    }
}

private struct SnippetTitleLine: View {
    let snippet: ClipboardItem
    let title: String
    @State private var extraLines = 0

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .layoutPriority(-1)
            if extraLines > 0 {
                Text("+\(extraLines) lines")
                    .font(.caption2.monospacedDigit())
                    .pestoCaption()
                    .padding(.horizontal, 6)
                    .overlay(Capsule().strokeBorder(.quaternary))
                    .fixedSize()
                    .accessibilityLabel(String(localized: "\(extraLines) more lines"))
            }
        }
        .task(id: "\(snippet.id)-\(snippet.textLength)") {
            extraLines = TextLines.extra(in: ClipText.full(of: snippet))
        }
    }
}
