// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The questions a snippet asks before it is copied. `{{clipboard}}` is filled only from what the person pastes with
/// the system Paste button here; Pesto never reads the clipboard for it on its own.
struct SnippetFillSheet: View {
    let request: SnippetFillRequest
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @State private var fills: SnippetFills
    @State private var pasted = ""
    @State private var selectedText = ""

    init(request: SnippetFillRequest) {
        self.request = request
        _fills = State(initialValue: request.initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !request.plan.fields.isEmpty {
                    Section {
                        ForEach(request.plan.fields) { field in
                            row(field)
                        }
                    }
                }
                if request.plan.usesClipboard {
                    Section {
                        PasteButton(payloadType: String.self) { strings in
                            pasted = strings.first ?? ""
                        }
                        .accessibilityIdentifier(MobileAccessibilityID.snippetPasteButton)
                        if !pasted.isEmpty {
                            Text(pasted).lineLimit(3).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Clipboard")
                    } footer: {
                        Text("Paste fills the clipboard placeholder. Without it, that placeholder stays empty.")
                    }
                }
                if request.plan.usesSelection {
                    Section {
                        TextField("Selected text", text: $selectedText, axis: .vertical)
                            .lineLimit(1...4)
                        PasteButton(payloadType: String.self) { strings in
                            selectedText = strings.first ?? ""
                        }
                    } header: {
                        Text("Selected text")
                    }
                }
                if !request.plan.leftEmpty.isEmpty {
                    Section {
                        Text("The app name is not available on iPhone and iPad, so it stays empty.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { appState.pendingFill = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        if appState.copyFilled(
                            request, fills: fills, pastedClipboard: pasted, selectedText: selectedText
                        ) {
                            library.didCopy(request.id)
                        }
                    }
                    .accessibilityIdentifier(MobileAccessibilityID.snippetCopyButton)
                }
            }
        }
        .accessibilityIdentifier(MobileAccessibilityID.snippetFillSheet)
    }

    @ViewBuilder
    private func row(_ field: SnippetField) -> some View {
        switch field.kind {
        case let .text(multiline):
            TextField(field.label, text: textBinding(field), axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 1...6 : 1...1)
        case let .choice(options):
            Picker(field.label, selection: textBinding(field)) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        case .optional:
            Toggle(field.label, isOn: includedBinding(field))
        }
    }

    private func textBinding(_ field: SnippetField) -> Binding<String> {
        Binding(
            get: { fills.values[field.label] ?? "" },
            set: { fills.values[field.label] = $0 }
        )
    }

    private func includedBinding(_ field: SnippetField) -> Binding<Bool> {
        Binding(
            get: { fills.included.contains(field.label) },
            set: { if $0 { fills.included.insert(field.label) } else { fills.included.remove(field.label) } }
        )
    }
}
