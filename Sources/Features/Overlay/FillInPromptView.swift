// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

@Observable
final class FillInPromptModel {
    let title: String
    let fields: [SnippetField]
    var fills: SnippetFills
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    init(title: String, fields: [SnippetField], fills: SnippetFills) {
        self.title = title
        self.fields = fields
        self.fills = fills
    }
}

/// The small prompt a snippet shows when it is pasted and asks for values: one row per field, Tab between them, Return
/// pastes, Escape cancels.
struct FillInPromptView: View {
    @Environment(\.pestoAccent) private var accent
    @State var model: FillInPromptModel
    @FocusState private var focused: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title)
                .scaledFont(size: 13, weight: .semibold, maxScale: 1.3)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.fields) { field in
                row(for: field)
            }
            HStack {
                Text("Esc cancels").pestoCaption()
                Spacer()
                Button("Cancel") { model.onCancel?() }
                    .keyboardShortcut(.cancelAction)
                Button("Paste") { model.onSubmit?() }
                    .buttonStyle(.pestoProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier(AccessibilityID.fillInPasteButton)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background { shape.fill(Color.opaqueSurface.opacity(0.94)).adaptiveMaterialBackground(in: shape) }
        .overlay { shape.strokeBorder(.primary.opacity(0.14), lineWidth: 1) }
        .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
        .onAppear { focused = model.fields.first(where: { isTyped($0) })?.label }
    }

    private func isTyped(_ field: SnippetField) -> Bool {
        if case .text = field.kind { return true }
        return false
    }

    @ViewBuilder
    private func row(for field: SnippetField) -> some View {
        switch field.kind {
        case let .text(multiline):
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label).pestoCaption()
                if multiline {
                    TextEditor(text: binding(field.label))
                        .scaledFont(size: 12)
                        .frame(height: 72)
                        .focused($focused, equals: field.label)
                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.35)) }
                } else {
                    TextField(field.label, text: binding(field.label))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: field.label)
                        .onSubmit { model.onSubmit?() }
                }
            }
        case let .choice(options):
            Picker(field.label, selection: binding(field.label)) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        case .optional:
            Toggle(field.label, isOn: Binding(
                get: { model.fills.included.contains(field.label) },
                set: { on in
                    if on { model.fills.included.insert(field.label) } else { model.fills.included.remove(field.label) }
                }
            ))
            .tint(accent)
        }
    }

    private func binding(_ label: String) -> Binding<String> {
        Binding(get: { model.fills.values[label] ?? "" }, set: { model.fills.values[label] = $0 })
    }
}
