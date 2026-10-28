// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The fields a snippet asks for, as chips under the text. A chip renames its field everywhere in the text.
struct SnippetFieldChips: View {
    @Binding var text: String
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        let fields = FillInParser.fields(in: text)
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                PlaceholderFlowLayout(spacing: 6) {
                    Text("Asks for").pestoCaption()
                    ForEach(fields) { field in
                        FieldChip(field: field, text: $text)
                    }
                }
                Text("Pesto asks for these when you paste. Click a name to rename it.").pestoCaption()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What this snippet asks for when you paste")
        }
    }
}

private struct FieldChip: View {
    let field: SnippetField
    @Binding var text: String
    @Environment(\.pestoAccent) private var accent
    @State private var isRenaming = false
    @State private var name = ""

    private var symbol: String {
        switch field.kind {
        case .text: "character.cursor.ibeam"
        case .choice: "list.bullet"
        case .optional: "switch.2"
        }
    }

    var body: some View {
        Button {
            name = field.label
            isRenaming = true
        } label: {
            Label(field.label, systemImage: symbol)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(accent)
        .help("Rename this field")
        .popover(isPresented: $isRenaming) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
                HStack {
                    Spacer()
                    Button("Cancel") { isRenaming = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Rename", action: commit)
                        .buttonStyle(.pestoProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(FillInParser.renaming(field.label, to: name, in: text) == nil)
                }
            }
            .padding(14)
            .frame(width: 240)
        }
    }

    private func commit() {
        if let renamed = FillInParser.renaming(field.label, to: name, in: text) { text = renamed }
        isRenaming = false
    }
}
