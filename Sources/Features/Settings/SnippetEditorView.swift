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
    @FocusState private var focus: Field?
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
            row("Text", alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    SnippetBodyEditor(
                        text: $draft.text,
                        pendingInsertion: $pendingInsertion,
                        focusOnAppear: !(draft.clipID == nil && draft.text.isEmpty)
                    )
                    .focused($focus, equals: .text)
                    .padding(6)
                    .frame(minHeight: 96, maxHeight: 180)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.35)) }
                    placeholderChips
                    if state == .needsPlaceholder {
                        Text("Add a placeholder, like {{date}}, so Pesto can fill it in when you paste.")
                            .pestoCaption()
                            .accessibilityIdentifier(AccessibilityID.snippetNeedsPlaceholder)
                    }
                }
            }
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
            HStack(spacing: 8) {
                Text("Esc cancels. \u{2318}Return saves.").pestoCaption()
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
        .padding(.vertical, 6)
        .onAppear { focus = draft.clipID == nil && draft.text.isEmpty ? .name : .text }
    }

    private var placeholderChips: some View {
        PlaceholderFlowLayout(spacing: 6) {
            Text("Insert").pestoCaption()
            SnippetFieldMenu { token in
                pendingInsertion = SnippetInsertionRequest(token: token)
            }
            ForEach(SnippetDraft.placeholders, id: \.token) { placeholder in
                Button(placeholder.token) {
                    pendingInsertion = SnippetInsertionRequest(token: placeholder.token)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .help(placeholder.meaning)
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

private struct PlaceholderFlowLayout: Layout {
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

private struct SnippetBodyEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var pendingInsertion: SnippetInsertionRequest?
    let focusOnAppear: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = UndoableSnippetTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.setAccessibilityIdentifier(AccessibilityID.snippetTextEditor)
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        textView.focusOnFirstWindowMove = focusOnAppear

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? UndoableSnippetTextView else { return }
        context.coordinator.textBinding = $text
        if textView.string != text {
            let previousRange = textView.selectedRange()
            textView.string = text
            let clampedLocation = min(previousRange.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
        }
        if let insertion = pendingInsertion, context.coordinator.lastInsertionID != insertion.id {
            context.coordinator.lastInsertionID = insertion.id
            let step = SnippetDraft.inserting(insertion.token, into: textView.string, at: textView.selectedRange())
            if textView.shouldChangeText(in: step.clampedRange, replacementString: insertion.token) {
                textView.replaceCharacters(in: step.clampedRange, with: insertion.token)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: step.cursorLocation, length: 0))
                let newText = textView.string
                DispatchQueue.main.async {
                    context.coordinator.textBinding.wrappedValue = newText
                }
            }
            textView.window?.makeFirstResponder(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var textBinding: Binding<String>
        weak var textView: NSTextView?
        var lastInsertionID: UUID?

        init(text: Binding<String>) {
            textBinding = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let string = tv.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.textBinding.wrappedValue != string {
                    self.textBinding.wrappedValue = string
                }
            }
        }
    }
}

private final class UndoableSnippetTextView: NSTextView {
    var focusOnFirstWindowMove = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusOnFirstWindowMove, let window {
            focusOnFirstWindowMove = false
            window.makeFirstResponder(self)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == .command {
            switch key {
            case "z":
                undoManager?.undo()
                return true
            case "x":
                cut(nil)
                return true
            case "c":
                copy(nil)
                return true
            case "v":
                paste(nil)
                return true
            case "a":
                selectAll(nil)
                return true
            default:
                break
            }
        } else if flags == [.command, .shift], key == "z" {
            undoManager?.redo()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
