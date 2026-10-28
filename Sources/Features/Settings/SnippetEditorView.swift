// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// A snippet being made or edited. `clipID` is nil for a new one.
struct SnippetEditorDraft: Identifiable, Equatable {
    let id = UUID()
    /// The clip being edited, nil for a new snippet.
    var clipID: UUID?
    var title: String
    var text: String
    /// The suggestion row the editor opens in place of, so it appears where the person clicked and not at the top.
    var anchorID: String?
    /// The shortcut the person asked for with a new snippet, from the next free slot.
    var shortcutSlot: Int?

    static func new(text: String = "", title: String = "", anchorID: String? = nil) -> SnippetEditorDraft {
        SnippetEditorDraft(clipID: nil, title: title, text: text, anchorID: anchorID)
    }
}

struct SnippetInsertionRequest: Equatable {
    let id = UUID()
    let token: String
}

/// Make or edit a snippet where it lives in the list: a name, the text, the placeholders to put in it, and what it will
/// paste as, drawn like a card on the shelf with the caret where `{{cursor}}` is. The same editor serves both, so
/// editing is the thing a person learns by adding. Designed on the "Pesto Snippet Editor" canvas.
struct SnippetEditorView: View {
    private enum Field {
        case name, text
    }

    @Environment(\.pestoAccent) private var accent
    @State var draft: SnippetEditorDraft
    @State private var pendingInsertion: SnippetInsertionRequest?
    @State private var suggestingNames = false
    @State private var namesFailed = false
    @FocusState private var focus: Field?
    /// The lowest free ⌃1 to ⌃9, or nil when none is: a new snippet can claim it when it is saved.
    var freeShortcutSlot: Int?
    let onSave: (SnippetEditorDraft) -> Void
    let onCancel: () -> Void

    private var state: SnippetDraft {
        SnippetDraft.evaluate(draft.text)
    }

    private var preview: AttributedString {
        var result = AttributedString()
        var inOptional = false
        for piece in SnippetPreview.pieces(from: draft.text) {
            switch piece {
            case let .text(text):
                var run = AttributedString(text)
                if inOptional { run.foregroundColor = .secondary }
                result += run
            case let .field(label, hint, kind):
                var name = "\u{2009}\(label)"
                if kind == .input, let hint { name += ": \(hint)" }
                if kind == .choice { name += " \u{25BE}" }
                name += "\u{2009}"
                var chip = AttributedString(name)
                let tint = kind == .context ? Color.secondary : accent
                chip.foregroundColor = tint
                chip.backgroundColor = tint.opacity(0.18)
                result += chip
            case let .optionalStart(label):
                var tag = AttributedString("\u{2039}\(label)\u{203A} ")
                tag.foregroundColor = .secondary
                result += tag
                inOptional = true
            case .optionalEnd:
                inOptional = false
            case .caret:
                var caret = AttributedString("\u{258F}")
                caret.foregroundColor = accent
                result += caret
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Name") {
                TextField("", text: $draft.title, prompt: Text("Thank-you reply"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .name)
                    .onSubmit(save)
                    .accessibilityIdentifier(AccessibilityID.snippetNameField)
            }
            textColumn
            questionsPanel
            row("Pastes as", alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    previewCard
                    Text(
                        "Highlighted names are asked for when you paste. A dimmed part is optional. "
                            + "The caret lands where {{cursor}} is, in apps that let Pesto move it."
                    )
                    .pestoCaption()
                }
            }
            footer
        }
        .padding(.vertical, 6)
        .onAppear { focus = draft.clipID == nil && draft.text.isEmpty ? .name : .text }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text").scaledFont(size: 12, weight: .semibold).pestoQuiet()
            SnippetBodyEditor(
                text: $draft.text,
                pendingInsertion: $pendingInsertion,
                focusOnAppear: !(draft.clipID == nil && draft.text.isEmpty),
                accent: NSColor(accent)
            )
            .focused($focus, equals: .text)
            .padding(6)
            .frame(minHeight: 120, maxHeight: 200)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.35)) }
            HStack(spacing: 6) {
                SnippetFieldMenu { token in pendingInsertion = SnippetInsertionRequest(token: token) }
                FillFromMacMenu { token in pendingInsertion = SnippetInsertionRequest(token: token) }
            }
            if state == .needsPlaceholder {
                Text("Add a question or a fill, like {{date}}, so Pesto can fill it in when you paste.")
                    .pestoCaption()
                    .accessibilityIdentifier(AccessibilityID.snippetNeedsPlaceholder)
            }
        }
    }

    private var questionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("When you paste").scaledFont(size: 12, weight: .semibold).pestoQuiet()
                Spacer()
                suggestNamesButton
            }
            SnippetQuestionRows(text: $draft.text)
            suggestNamesNote
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            shortcutRow
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.pestoProminent)
                .disabled(state != .ready)
                .accessibilityIdentifier(AccessibilityID.snippetSaveButton)
        }
    }

    @ViewBuilder
    private var shortcutRow: some View {
        if draft.clipID == nil, let slot = freeShortcutSlot {
            Toggle(isOn: Binding(
                get: { draft.shortcutSlot != nil },
                set: { draft.shortcutSlot = $0 ? slot : nil }
            )) {
                Text("Also paste it with \u{2303}\(slot) from any app")
            }
            .toggleStyle(.checkbox)
        } else {
            Text("Esc cancels. \u{2318}Return saves.").pestoCaption()
        }
    }

    private var namedFields: Bool {
        FillInParser.fields(in: draft.text).contains { $0.kind != .optional }
    }

    @ViewBuilder
    private var suggestNamesButton: some View {
        let availability = AIAvailability.current
        if namedFields, availability.presentation != .hidden {
            Button("Suggest Names") { suggestNames() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!availability.isAvailable || suggestingNames)
        }
    }

    @ViewBuilder
    private var suggestNamesNote: some View {
        let availability = AIAvailability.current
        if namedFields, availability.presentation != .hidden {
            if !availability.isAvailable {
                Text(availability.message).pestoCaption()
            } else if namesFailed {
                Text("Couldn\u{2019}t suggest names. The questions keep their names.").pestoCaption()
            }
        }
    }

    private func suggestNames() {
        suggestingNames = true
        namesFailed = false
        let template = draft.text
        Task {
            let renamed = await SnippetNaming.suggest(for: template, using: AIActionCoordinator.onDevice)
            suggestingNames = false
            if let renamed, draft.text == template {
                draft.text = renamed
            } else {
                namesFailed = true
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text("Snippet").scaledFont(size: 11, weight: .semibold)
            }
            .pestoQuiet()
            ScrollView(.vertical, showsIndicators: true) {
                Text(preview)
                    .id(draft.text)
                    .scaledFont(size: 11.5, design: .monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier(AccessibilityID.snippetPreview)
            }
            .frame(minHeight: 48, maxHeight: 160)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.14)) }
    }

    private func row(
        _ label: LocalizedStringKey, alignment: VerticalAlignment = .center, @ViewBuilder content: () -> some View
    )
    -> some View {
        HStack(alignment: alignment, spacing: 10) {
            Text(label)
                .scaledFont(size: 12, weight: .semibold)
                .pestoQuiet()
                .frame(width: 64, alignment: .leading)
                .padding(.top, alignment == .top ? 6 : 0)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() {
        guard state == .ready else { return }
        onSave(draft)
    }
}

struct PlaceholderFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            usedWidth = max(usedWidth, currentX + size.width)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: usedWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
