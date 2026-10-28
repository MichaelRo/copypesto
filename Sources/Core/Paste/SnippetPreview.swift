// SPDX-License-Identifier: MIT
import Foundation

/// What the snippet editor shows under the text: the snippet as it will paste, split where the caret will land
/// (`{{cursor}}`), so a person sees the placeholders filled in and the caret before they save.
public struct SnippetPreview: Equatable, Sendable {
    /// A piece of the snippet as the editor draws it: plain text, a field the paste will ask for or fill from context,
    /// the start and end of an optional section, and where the caret lands.
    public enum Piece: Equatable, Sendable {
        case text(String)
        case field(label: String, hint: String?, kind: SnippetFieldKind)
        case optionalStart(label: String)
        case optionalEnd
        case caret
    }

    /// The snippet split into pieces, with the dates and the clipboard filled in and every question kept visible.
    public static func pieces(
        from template: String,
        at date: Date = .now,
        clipboardProvider: () -> String = TemplateExpander.liveClipboardText
    )
    -> [Piece] {
        let marked = FillInParser.markingFields(in: template)
        let expanded = TemplateExpander.expansionWithCaret(
            of: marked, isSnippet: true, at: date, clipboardProvider: clipboardProvider
        )
        let text = expanded?.text ?? marked
        let characters = Array(text)
        let caretIndex = expanded?.charactersAfterCursor.map { characters.count - $0 }
        var pieces: [Piece] = []
        var plain = ""
        var index = 0
        func flush() {
            if !plain.isEmpty { pieces.append(.text(plain)) }
            plain = ""
        }
        while index <= characters.count {
            if index == caretIndex {
                flush()
                pieces.append(.caret)
            }
            guard index < characters.count else { break }
            let character = String(characters[index])
            if character == FillInParser.fieldStart, let end = characters[index...].firstIndex(where: {
                String($0) == FillInParser.fieldEnd
            }) {
                flush()
                let body = String(characters[(index + 1)..<end]).components(separatedBy: FillInParser.fieldSeparator)
                let kind: SnippetFieldKind = body[0] == "choice" ? .choice : body[0] == "context" ? .context : .input
                let hint = body.count > 2 && !body[2].isEmpty ? body[2] : nil
                pieces.append(.field(label: body.count > 1 ? body[1] : "", hint: hint, kind: kind))
                index = end + 1
            } else if character == FillInParser.optionalOpen, let end = characters[index...].firstIndex(where: {
                String($0) == FillInParser.optionalOpenEnd
            }) {
                flush()
                pieces.append(.optionalStart(label: String(characters[(index + 1)..<end])))
                index = end + 1
            } else if character == FillInParser.optionalClose {
                flush()
                pieces.append(.optionalEnd)
                index += 1
            } else {
                plain += character
                index += 1
            }
        }
        flush()
        return pieces
    }

    public let before: String
    public let after: String
    public let hasCaret: Bool

    public static func make(
        from template: String,
        at date: Date = .now,
        clipboardProvider: () -> String = TemplateExpander.liveClipboardText
    )
    -> SnippetPreview {
        guard let expanded = TemplateExpander.expansionWithCaret(
            of: template, isSnippet: true, at: date, clipboardProvider: clipboardProvider
        ) else {
            return SnippetPreview(before: template, after: "", hasCaret: false)
        }
        guard let afterCount = expanded.charactersAfterCursor else {
            return SnippetPreview(before: expanded.text, after: "", hasCaret: false)
        }
        let cut = expanded.text.index(expanded.text.endIndex, offsetBy: -afterCount)
        return SnippetPreview(
            before: String(expanded.text[..<cut]), after: String(expanded.text[cut...]), hasCaret: true
        )
    }
}

/// What a field in the editor's preview is: a typed value, a pick, or something filled in from context.
public enum SnippetFieldKind: Equatable, Sendable {
    case input, choice, context
}
