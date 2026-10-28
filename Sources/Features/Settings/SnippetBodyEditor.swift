// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

struct SnippetBodyEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var pendingInsertion: SnippetInsertionRequest?
    let focusOnAppear: Bool
    let accent: NSColor

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
        context.coordinator.accent = accent
        context.coordinator.highlight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? UndoableSnippetTextView else { return }
        context.coordinator.textBinding = $text
        context.coordinator.accent = accent
        if context.coordinator.pendingString == nil, textView.string != text {
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
        context.coordinator.highlight()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var textBinding: Binding<String>
        weak var textView: NSTextView?
        var lastInsertionID: UUID?
        /// What the person has typed that the binding has not caught up with: a refresh with the older text must not
        /// overwrite it, or fast typing loses characters.
        var pendingString: String?
        var accent = NSColor.labelColor

        init(text: Binding<String>) {
            textBinding = text
        }

        /// Colors the questions with the accent and the fills from the Mac quietly, so the text shows what is asked.
        func highlight() {
            guard let storage = textView?.textStorage else { return }
            let whole = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: whole)
            storage.removeAttribute(.backgroundColor, range: whole)
            for item in FillInParser.highlights(in: storage.string) {
                switch item.kind {
                case .question:
                    storage.addAttribute(.foregroundColor, value: accent, range: item.range)
                    storage.addAttribute(.backgroundColor, value: accent.withAlphaComponent(0.14), range: item.range)
                case .fill:
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: item.range)
                }
            }
            storage.endEditing()
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            highlight()
            let string = tv.string
            pendingString = string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.textBinding.wrappedValue != string {
                    self.textBinding.wrappedValue = string
                }
                if self.pendingString == string { self.pendingString = nil }
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
