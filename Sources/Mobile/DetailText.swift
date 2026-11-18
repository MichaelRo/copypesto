// SPDX-License-Identifier: MIT
import Foundation

/// How much of a clip's text the detail lays out: a text of several megabytes in one selectable `Text` costs seconds
/// and memory, so past the limit the detail shows the beginning, says so, and Copy and Share still use the whole.
struct DetailText: Equatable {
    static let characterLimit = 20_000

    let shown: String
    let isTruncated: Bool

    static func make(_ text: String, limit: Int = characterLimit) -> DetailText {
        guard text.utf8.count > limit else { return DetailText(shown: text, isTruncated: false) }
        guard let cut = text.index(text.startIndex, offsetBy: limit, limitedBy: text.endIndex),
              cut < text.endIndex else
        {
            return DetailText(shown: text, isTruncated: false)
        }
        return DetailText(shown: String(text[..<cut]), isTruncated: true)
    }
}
