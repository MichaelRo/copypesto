// SPDX-License-Identifier: MIT
import Foundation

/// The text in the keyboard's own search field (ADR 0063). Its letter keys type here and nowhere else: never into the
/// app the person is writing in. It lives only while the search page is open.
public struct KeyboardQuery: Equatable, Sendable {
    public static let maxLength = 64

    public private(set) var text = ""

    public init(starting word: String? = nil) {
        text = String((word ?? "").prefix(Self.maxLength))
    }

    /// What to search for: the text without spaces at its ends, once it holds a letter or digit.
    public var search: String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.contains { $0.isLetter || $0.isNumber } ? trimmed : nil
    }

    public mutating func type(_ characters: String) {
        text = String((text + characters).prefix(Self.maxLength))
    }

    public mutating func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }

    public mutating func clear() {
        text = ""
    }
}
