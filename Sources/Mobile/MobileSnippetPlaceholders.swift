// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftUI

/// Built-in fills and preview/insertion helpers for the iOS snippet editor (Mac-only `{{selection}}` and `{{app}}` are
/// excluded).
enum MobileSnippetPlaceholders {
    private static let macOnlyTokens: Set<String> = ["{{selection}}", "{{app}}"]

    static let automaticFills: [SnippetPlaceholder] = SnippetDraft.placeholders.filter {
        !macOnlyTokens.contains($0.token)
    }

    static func canSave(text: String) -> Bool {
        SnippetDraft.evaluate(text) == .ready || !FillInParser.detectedVariables(in: text).isEmpty
    }

    static func preparedTextForSave(_ text: String) -> String? {
        let prepared = if SnippetDraft.evaluate(text) != .ready, !FillInParser.detectedVariables(in: text).isEmpty {
            FillInParser.convertingAllVariables(in: text)
        } else {
            text
        }
        return SnippetDraft.evaluate(prepared) == .ready ? prepared : nil
    }

    static func inserting(
        _ token: String,
        into text: String,
        selection: TextSelection?
    )
        -> (text: String, selection: TextSelection)
    {
        let range = utf16Range(from: selection, in: text)
        let step = SnippetDraft.inserting(token, into: text, at: range)
        let index = String.Index(utf16Offset: step.cursorLocation, in: step.text)
        return (step.text, TextSelection(insertionPoint: index))
    }

    private static func utf16Range(from selection: TextSelection?, in text: String) -> NSRange {
        let selectedRange: Range<String.Index>? = switch selection?.indices {
        case let .selection(range):
            range
        case let .multiSelection(ranges):
            ranges.ranges.first
        case nil:
            nil
        @unknown default:
            nil
        }
        guard let range = selectedRange else {
            return NSRange(location: (text as NSString).length, length: 0)
        }
        let lower = min(max(range.lowerBound, text.startIndex), text.endIndex)
        let upper = min(max(range.upperBound, lower), text.endIndex)
        return NSRange(lower..<upper, in: text)
    }

    static func previewString(from text: String, accent: Color) -> AttributedString {
        var result = AttributedString()
        var inOptional = false
        for piece in SnippetPreview.pieces(from: text, clipboardProvider: { "" }) {
            switch piece {
            case let .text(chunk):
                var run = AttributedString(chunk)
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
}
