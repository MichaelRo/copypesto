// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// "Add Question…" in the snippet editor: pick the kind of value a snippet asks for, name it, and Pesto writes the
/// token
/// so nobody types attributes by hand.
struct SnippetFieldMenu: View {
    private enum Choice: String, CaseIterable, Identifiable {
        case text = "Text Field…"
        case multiline = "Multi-Line Field…"
        case choice = "Choice…"
        case optional = "Optional Section…"

        var id: String {
            rawValue
        }
    }

    let insert: (String) -> Void

    @State private var choice: Choice?
    @State private var label = ""
    @State private var detail = ""

    var body: some View {
        PopUpMenuButton(items: Choice.allCases.map { option in
            .action(String(localized: String.LocalizationValue(option.rawValue))) { open(option) }
        }) {
            Text("Add Question\u{2026}")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .fixedSize()
        .help("Ask for a value when you paste")
        .popover(isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } })) {
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Label", text: $label, prompt: Text("Customer name"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            if let detailTitle {
                TextField(detailTitle, text: $detail, prompt: Text(detailPrompt))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
            }
            HStack {
                Spacer()
                Button("Cancel") { choice = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Insert", action: commit)
                    .buttonStyle(.pestoProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(field == nil)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var detailTitle: LocalizedStringKey? {
        switch choice {
        case .text, .multiline: "Default"
        case .choice: "Options"
        default: nil
        }
    }

    private var detailPrompt: String {
        choice == .choice ? "Hi, Hello, Dear" : "Optional"
    }

    private var field: SnippetField? {
        let name = label.trimmingCharacters(in: .whitespaces)
        let extra = detail.trimmingCharacters(in: .whitespaces)
        let built: SnippetField? = switch choice {
        case .text: SnippetField(label: name, kind: .text(multiline: false), defaultValue: extra.isEmpty ? nil : extra)
        case .multiline: SnippetField(
                label: name,
                kind: .text(multiline: true),
                defaultValue: extra.isEmpty ? nil : extra
            )
        case .choice:
            SnippetField(
                label: name, kind: .choice(extra.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }),
                defaultValue: nil
            )
        case .optional: SnippetField(label: name, kind: .optional, defaultValue: nil)
        case nil: nil
        }
        guard let built, FillInParser.fields(in: built.insertion).first?.label == name else { return nil }
        return built
    }

    private func open(_ option: Choice) {
        label = ""
        detail = ""
        choice = option
    }

    private func commit() {
        guard let field else { return }
        insert(field.insertion)
        choice = nil
    }
}
