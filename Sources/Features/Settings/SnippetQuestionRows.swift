// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The questions a snippet asks when it is pasted, one row each, and the fills Pesto makes by itself. A row renames,
/// changes and removes its question everywhere it appears in the text.
struct SnippetQuestionRows: View {
    @Binding var text: String

    var body: some View {
        let questions = FillInParser.fields(in: text)
        VStack(alignment: .leading, spacing: 8) {
            if questions.isEmpty {
                Text("Nothing is asked yet. Add a question, and Pesto asks for it when you paste.")
                    .pestoCaption()
            } else {
                ForEach(questions) { question in
                    QuestionRow(question: question, text: $text)
                }
            }
            fills
        }
    }

    @ViewBuilder
    private var fills: some View {
        let used =
            Array(NSOrderedSet(array: FillInParser.highlights(in: text).filter { $0.kind == .fill }.map(\.label)))
            .compactMap { $0 as? String }
        if !used.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Filled in by Pesto").pestoCaption()
                PlaceholderFlowLayout(spacing: 6) {
                    ForEach(used, id: \.self) { label in
                        Text(verbatim: label)
                            .scaledFont(size: 11, design: .monospaced)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay { Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
                            .pestoQuiet()
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filled in by Pesto when you paste")
        }
    }
}

private struct QuestionRow: View {
    let question: SnippetField
    @Binding var text: String
    @Environment(\.pestoAccent) private var accent
    @State private var name: String
    @State private var isOpen = false
    @FocusState private var nameFocused: Bool

    init(question: SnippetField, text: Binding<String>) {
        self.question = question
        _text = text
        _name = State(initialValue: question.label)
    }

    private var symbol: String {
        switch question.kind {
        case .text: "character.cursor.ibeam"
        case .choice: "list.bullet"
        case .optional: "switch.2"
        }
    }

    private var kindName: LocalizedStringKey {
        switch question.kind {
        case .text: "Text"
        case .choice: "Choice"
        case .optional: "Optional section"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(accent).frame(width: 18).accessibilityHidden(true)
                TextField("", text: $name, prompt: Text("Question name"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .scaledFont(size: 12, weight: .semibold)
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
                    .accessibilityLabel("Question name")
                    .accessibilityIdentifier(AccessibilityID.snippetQuestionName)
                Text(kindName).pestoCaption()
                Spacer(minLength: 4)
                if question.kind != .optional {
                    Button {
                        isOpen.toggle()
                    } label: {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .help("Default value and options")
                    .accessibilityLabel(isOpen ? "Hide details" : "Show details")
                }
                Button {
                    if let removed = FillInParser.removing(question.label, from: text) { text = removed }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Remove this question")
                .accessibilityLabel("Remove \(question.label)")
            }
            if isOpen { details }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.08)))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.25)) }
        .onChange(of: question.label) { _, label in name = label }
    }

    @ViewBuilder
    private var details: some View {
        switch question.kind {
        case let .text(multiline):
            TextField("", text: defaultBinding, prompt: Text("Starts with (optional)"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Starts with")
            Toggle("A box for several lines", isOn: Binding(
                get: { multiline },
                set: { change(SnippetField(
                    label: question.label,
                    kind: .text(multiline: $0),
                    defaultValue: question.defaultValue
                )) }
            ))
            .toggleStyle(.checkbox)
        case let .choice(options):
            TextField("", text: Binding(
                get: { options.joined(separator: ", ") },
                set: { value in
                    let list = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    guard !list.isEmpty else { return }
                    change(SnippetField(label: question.label, kind: .choice(list), defaultValue: list.first))
                }
            ), prompt: Text("Hi, Hello, Dear"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Options, separated by commas")
        case .optional:
            EmptyView()
        }
    }

    private var defaultBinding: Binding<String> {
        Binding(
            get: { question.defaultValue ?? "" },
            set: { value in
                change(SnippetField(
                    label: question.label,
                    kind: question.kind,
                    defaultValue: value.isEmpty ? nil : value
                ))
            }
        )
    }

    private func change(_ field: SnippetField) {
        if let updated = FillInParser.updating(question.label, to: field, in: text) { text = updated }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != question.label else { return }
        if let renamed = FillInParser.renaming(question.label, to: trimmed, in: text) {
            text = renamed
        } else {
            name = question.label
        }
    }
}
