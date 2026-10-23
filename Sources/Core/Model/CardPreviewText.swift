// SPDX-License-Identifier: MIT

/// What a text card draws of a clip, and what its footer says about the lines. Display only: the stored clip, the
/// search text and what a paste writes are never touched.
public enum CardPreviewText {
    /// How much of a clip's text is kept as its preview.
    public static let previewLength = 500

    /// The preview with every Unicode line break as `\n`, no blank lines or indent at the start, no whitespace at the
    /// end
    /// and at most one blank line in a row.
    public static func display(_ text: String) -> String {
        var lines: [String] = []
        var current = ""
        func endLine() {
            lines.append(current.allSatisfy(\.isWhitespace) ? "" : current)
            current = ""
        }
        for character in text {
            if character.isNewline { endLine() } else { current.append(character) }
        }
        endLine()

        var shown: [String] = []
        for line in lines {
            if line.isEmpty {
                if shown.isEmpty || shown.last?.isEmpty == true { continue }
            } else if shown.isEmpty {
                shown.append(String(line.drop(while: \.isWhitespace)))
                continue
            }
            shown.append(line)
        }
        while shown.last?.isEmpty == true {
            shown.removeLast()
        }
        guard var last = shown.popLast() else { return "" }
        while last.last?.isWhitespace == true {
            last.removeLast()
        }
        shown.append(last)
        return shown.joined(separator: "\n")
    }

    /// The runs of text between blank lines, from the compacted preview.
    public static func paragraphs(_ text: String) -> [String] {
        let shown = display(text)
        guard !shown.isEmpty else { return [] }
        return shown.components(separatedBy: "\n\n")
    }

    /// The number of lines for the footer, or nil: only when the clip has more than one line and the whole of it is in
    /// the preview, because a count of the first 500 characters of a longer clip would be wrong.
    public static func footerLineCount(of preview: String, textLength: Int) -> Int? {
        let wholeTextIsShown = textLength > 0 ? textLength <= previewLength : preview.count < previewLength
        guard wholeTextIsShown else { return nil }
        let count = TextLines.count(in: preview)
        return count > 1 ? count : nil
    }
}
