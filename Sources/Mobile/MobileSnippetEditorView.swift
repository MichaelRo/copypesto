// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Creates a new snippet or edits an existing one with fill-in questions, automatic fills, and a live preview.
struct MobileSnippetEditorView: View {
    let target: LibraryModel.SnippetEditorTarget

    @Environment(MobileAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pestoAccent) private var accent

    @State private var title: String
    @State private var text: String
    @State private var selection: TextSelection?
    @State private var pendingQuestion: QuestionChoice?
    @State private var isSaving = false
    @State private var isConfirmingDiscard = false
    @FocusState private var focusedField: Field?

    private let initialTitle: String
    private let initialText: String

    private enum Field {
        case title, body
    }

    private enum QuestionChoice: String, CaseIterable, Identifiable {
        case text = "Text Field"
        case multiline = "Multi-Line Field"
        case choice = "Choice\u{2026}"
        case optional = "Optional Section"

        var id: String {
            rawValue
        }
    }

    init(target: LibraryModel.SnippetEditorTarget) {
        self.target = target
        switch target {
        case .new:
            initialTitle = ""
            initialText = ""
        case let .edit(_, title, text):
            initialTitle = title
            initialText = text
        }
        _title = State(initialValue: initialTitle)
        _text = State(initialValue: initialText)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var hasChanges: Bool {
        title != initialTitle || text != initialText
    }

    private var canSave: Bool {
        !isSaving && MobileSnippetPlaceholders.canSave(text: text)
    }

    private var needsPlaceholderHint: Bool {
        SnippetDraft.evaluate(text) == .needsPlaceholder && FillInParser.detectedVariables(in: text).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Thank-you reply", text: $title)
                        .focused($focusedField, equals: .title)
                        .accessibilityIdentifier(MobileAccessibilityID.snippetTitleField)
                }
                Section {
                    TextEditor(text: $text, selection: $selection)
                        .font(.body.monospaced())
                        .frame(minHeight: 140)
                        .focused($focusedField, equals: .body)
                        .accessibilityIdentifier(MobileAccessibilityID.snippetBodyEditor)
                    editorMenus
                } header: {
                    Text("Template")
                } footer: {
                    if needsPlaceholderHint {
                        Text("Add a question or a fill, like {{date}}, so Pesto can fill it in when you copy.")
                    }
                }
                Section("Questions") {
                    MobileSnippetQuestionList(text: $text)
                }
                Section {
                    Text(MobileSnippetPlaceholders.previewString(from: text, accent: accent))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(MobileAccessibilityID.snippetPreview)
                } header: {
                    Text("Copies as")
                } footer: {
                    Text(
                        "Highlighted names are asked for when you copy. A dimmed part is optional. " +
                            "The {{cursor}} marker is removed when copied."
                    )
                }
                if let notice = appState.notice, notice.isProblem {
                    Section {
                        Label(notice.text, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isNew ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!canSave)
                        .accessibilityIdentifier(MobileAccessibilityID.snippetSaveButton)
                }
            }
            .onAppear {
                focusedField = isNew && text.isEmpty ? .title : .body
            }
            .confirmationDialog(
                "Discard changes?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .sheet(item: $pendingQuestion) { choice in
                AddQuestionSheet(choice: choice) { insertion in
                    insert(insertion)
                }
                .presentationDetents([.medium])
            }
        }
        .accessibilityIdentifier(MobileAccessibilityID.snippetEditor)
        .interactiveDismissDisabled(hasChanges)
    }

    private var editorMenus: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(QuestionChoice.allCases) { option in
                        Button(String(localized: String.LocalizationValue(option.rawValue))) {
                            pendingQuestion = option
                        }
                    }
                } label: {
                    Label("Add Question\u{2026}", systemImage: "plus.bubble")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier(MobileAccessibilityID.snippetAddQuestionMenu)

                Menu {
                    ForEach(MobileSnippetPlaceholders.automaticFills, id: \.token) { placeholder in
                        Button("\(placeholder.token)  \(placeholder.meaning)") {
                            insert(placeholder.token)
                        }
                    }
                } label: {
                    Label("Automatic Fill\u{2026}", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier(MobileAccessibilityID.snippetAutomaticFillMenu)

                if isNew {
                    Menu {
                        ForEach(SnippetStarters.all) { starter in
                            Button(starter.name) { applyStarter(starter) }
                        }
                    } label: {
                        Label("Starters\u{2026}", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func insert(_ token: String) {
        let step = MobileSnippetPlaceholders.inserting(token, into: text, selection: selection)
        text = step.text
        selection = step.selection
        focusedField = .body
    }

    private func applyStarter(_ starter: SnippetStarter) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || SnippetStarters.all.contains(where: { $0.name == trimmed }) {
            title = starter.name
        }
        text = starter.text
        selection = TextSelection(insertionPoint: text.endIndex)
    }

    private func cancel() {
        if hasChanges {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard let prepared = MobileSnippetPlaceholders.preparedTextForSave(text) else { return }
        isSaving = true
        let draftTitle = title
        Task {
            let saved: Bool = switch target {
            case .new:
                await appState.createSnippet(title: draftTitle, text: prepared)
            case let .edit(id, _, _):
                await appState.updateSnippet(id: id, title: draftTitle, text: prepared)
            }
            isSaving = false
            if saved { dismiss() }
        }
    }

    private struct AddQuestionSheet: View {
        let choice: QuestionChoice
        let onInsert: (String) -> Void

        @Environment(\.dismiss) private var dismiss
        @State private var label = ""
        @State private var detail = ""
        @FocusState private var focusesName: Bool

        private var detailTitle: LocalizedStringKey? {
            switch choice {
            case .text, .multiline: "Default value (optional)"
            case .choice: "Choices, separated by commas"
            case .optional: nil
            }
        }

        private var detailPrompt: String {
            choice == .choice ? "Hi, Hello, Dear" : "Leave empty to ask blank"
        }

        private var field: SnippetField? {
            let name = label.trimmingCharacters(in: .whitespaces)
            let extra = detail.trimmingCharacters(in: .whitespaces)
            let built = switch choice {
            case .text:
                SnippetField(label: name, kind: .text(multiline: false), defaultValue: extra.isEmpty ? nil : extra)
            case .multiline:
                SnippetField(label: name, kind: .text(multiline: true), defaultValue: extra.isEmpty ? nil : extra)
            case .choice:
                SnippetField(
                    label: name,
                    kind: .choice(extra.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }),
                    defaultValue: nil
                )
            case .optional:
                SnippetField(label: name, kind: .optional, defaultValue: nil)
            }
            guard FillInParser.fields(in: built.insertion).first?.label == name else { return nil }
            return built
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section("Question name") {
                        TextField("Customer name", text: $label)
                            .focused($focusesName)
                    }
                    if let detailTitle {
                        Section(detailTitle) {
                            TextField(detailPrompt, text: $detail)
                        }
                    }
                }
                .navigationTitle(String(localized: String.LocalizationValue(choice.rawValue)))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Insert") {
                            guard let field else { return }
                            onInsert(field.insertion)
                            dismiss()
                        }
                        .bold()
                        .disabled(field == nil)
                    }
                }
                .onAppear { focusesName = true }
            }
        }
    }
}
