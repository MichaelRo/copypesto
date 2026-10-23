// SPDX-License-Identifier: MIT
import Foundation

public enum TextLines {
    /// Lines in `text`; one trailing line break ends the last line instead of starting another.
    public static func count(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let body = text.last?.isNewline == true ? text.dropLast() : text[...]
        return body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    public static func extra(in text: String) -> Int {
        max(0, count(in: text) - 1)
    }
}
