// SPDX-License-Identifier: MIT
import Foundation

/// A ⌘ key that works while the shelf is open. A letter or punctuation key is matched by the character it prints, as a
/// menu item's key equivalent is, so ⌘A is the key labeled A on AZERTY and ⌘K is the K of a Dvorak keyboard. The key
/// code is the fallback when the system gives no character, and always the answer for the number row and Return.
public enum ShelfCommand: Equatable, Sendable {
    case search
    case previousCollection
    case nextCollection
    case settings
    case newCollection
    case pasteAll
    case pasteOneByOne
    case undo
    case redo
    case actions
    case copy
    case saveImage
    case quickLook
    case selectAll
    case pasteNth(Int)
    case returnKey
    case showHidden

    private static let byCharacter: [String: ShelfCommand] = [
        "f": .search, "[": .previousCollection, "]": .nextCollection, ",": .settings, "n": .newCollection,
        "p": .pasteAll, "z": .undo, "k": .actions, "c": .copy, "s": .saveImage, "y": .quickLook, "a": .selectAll,
        "e": .showHidden
    ]

    private static let byUSKeyCode: [UInt16: ShelfCommand] = [
        3: .search, 33: .previousCollection, 30: .nextCollection, 43: .settings, 45: .newCollection, 35: .pasteAll,
        40: .actions, 8: .copy, 1: .saveImage, 16: .quickLook, 0: .selectAll, 6: .undo, 14: .showHidden
    ]

    private static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    /// `shift` only changes two pairs: ⌘P pastes the selection at once and ⇧⌘P one clip at a time, ⌘Z undoes and ⇧⌘Z
    /// redoes. Every other command ignores it, as it always has.
    public static func resolve(characters: String?, keyCode: UInt16, shift: Bool = false) -> ShelfCommand? {
        if keyCode == 36 { return .returnKey }
        if let number = digitKeyCodes[keyCode] { return .pasteNth(number) }
        let command: ShelfCommand? = if let characters, !characters.isEmpty {
            byCharacter[characters.lowercased()]
        } else {
            byUSKeyCode[keyCode]
        }

        guard shift else { return command }
        return switch command {
        case .pasteAll: .pasteOneByOne
        case .undo: .redo
        default: command
        }
    }
}
