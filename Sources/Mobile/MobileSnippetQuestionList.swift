// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Editable fill-in questions, detected variables, and automatic fills for the iOS snippet editor.
struct MobileSnippetQuestionList: View {
    @Binding var text: String
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        let questions = FillInParser.fields(in: text)
        let detected = FillInParser.detectedVariables(in: text)
        let fills = usedFills
        if questions.isEmpty, detected.isEmpty, fills.isEmpty {
            Text("Nothing is asked yet. Add a question, and Pesto asks for it when you copy.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(questions) { question in
                QuestionRow(question: question, text: $text)
            }
            if !detected.isEmpty {
                detectedRows(detected)
            }
            if !fills.isEmpty {
                fillsRow(fills)
            }
        }
    }

    private var usedFills: [String] {
        var seen = Set<String>()
        return FillInParser.highlights(in: text)
            .filter { $0.kind == .fill }
            .map(\.label)
            .filter { seen.insert($0).inserted }
    }

    private func detectedRows(_ detected: [FillInParser.DetectedVariable]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Detected placeholders")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if detected.count > 1 {
                    Button("Turn All into Questions") {
                        text = FillInParser.convertingAllVariables(in: text)
                    }
                    .font(.footnote)
                }
            }
            ForEach(detected) { variable in
                HStack(spacing: 8) {
                    Text(verbatim: variable.rawToken)
                        .font(.footnote.monospaced())
                        .foregroundStyle(accent)
                    Spacer(minLength: 8)
                    Button(variable.isFill ? "Use Fill" : "Turn into Question") {
                        text = FillInParser.convertingVariable(variable, in: text)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func fillsRow(_ fills: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filled in by Pesto")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(fills, id: \.self) { label in
                        Text(verbatim: "{{\(label)}}")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 2)
    }

    private struct QuestionRow: View {
        let question: SnippetField
        @Binding var text: String
        @Environment(\.pestoAccent) private var accent
        @State private var name: String
        @State private var choicesText: String
        @State private var isExpanded = false
        @FocusState private var nameFocused: Bool
        @FocusState private var choicesFocused: Bool

        init(question: SnippetField, text: Binding<String>) {
            self.question = question
            _text = text
            _name = State(initialValue: question.label)
            if case let .choice(options) = question.kind {
                _choicesText = State(initialValue: options.joined(separator: ", "))
            } else {
                _choicesText = State(initialValue: "")
            }
        }

        private var symbol: String {
            switch question.kind {
            case .text: "character.cursor.ibeam"
            case .choice: "list.bullet"
            case .optional: "switch.2"
            }
        }

        private var kindLabel: LocalizedStringKey {
            switch question.kind {
            case .text: "Text"
            case .choice: "Choice"
            case .optional: "Optional section"
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .foregroundStyle(accent)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    TextField("Question name", text: $name)
                        .font(.subheadline.weight(.semibold))
                        .focused($nameFocused)
                        .onSubmit(commitName)
                        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
                    Spacer(minLength: 4)
                    if question.kind != .optional {
                        Button {
                            withAnimation(Motion.animation(.pestoQuick)) { isExpanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(kindLabel).font(.footnote).foregroundStyle(.secondary)
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isExpanded ? "Hide details" : "Show details")
                    } else {
                        Text(kindLabel).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        if let removed = FillInParser.removing(question.label, from: text) { text = removed }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(question.label)")
                }
                if isExpanded { details }
            }
            .padding(.vertical, 4)
            .onChange(of: question.label) { _, updated in name = updated }
            .onChange(of: question.kind) { _, updated in
                if case let .choice(options) = updated, !choicesFocused {
                    choicesText = options.joined(separator: ", ")
                }
            }
        }

        @ViewBuilder
        private var details: some View {
            switch question.kind {
            case let .text(multiline):
                TextField("Starts with (optional)", text: defaultBinding)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
                Toggle("Multiple lines", isOn: Binding(
                    get: { multiline },
                    set: {
                        change(SnippetField(
                            label: question.label,
                            kind: .text(multiline: $0),
                            defaultValue: question.defaultValue
                        ))
                    }
                ))
                .font(.subheadline)
            case .choice:
                TextField("Choices, separated by commas", text: $choicesText)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
                    .focused($choicesFocused)
                    .onSubmit(commitChoices)
                    .onChange(of: choicesText) { _, _ in commitChoices() }
                    .onChange(of: choicesFocused) { _, focused in
                        if !focused, case let .choice(options) = question.kind {
                            choicesText = options.joined(separator: ", ")
                        }
                    }
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

        private func commitChoices() {
            let list = choicesText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !list.isEmpty else { return }
            change(SnippetField(label: question.label, kind: .choice(list), defaultValue: list.first))
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
}
