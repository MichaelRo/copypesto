// SPDX-License-Identifier: MIT
import Foundation

/// A ⌘ key that works while the shelf is open. A letter or punctuation key is matched by the character it prints, as a
/// menu item's key equivalent is, so ⌘A is the key labeled A on AZERTY and ⌘K is the K of a Dvorak keyboard. The key
/// code is the fallback when the system gives no character, and always the answer for the number row and Return.
public enum ShelfCommand: Equatable, Sendable {
    case search
    case previousCollection
    case nextCollection
    case previousAppChip
    case nextAppChip
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
    /// ⌘I: the Clip Inspector for the focused clip (ADR 0071).
    case showDetails

    private static let byCharacter: [String: ShelfCommand] = [
        "f": .search, "[": .previousCollection, "]": .nextCollection, ",": .settings, "n": .newCollection,
        "p": .pasteAll, "z": .undo, "k": .actions, "c": .copy, "s": .saveImage, "y": .quickLook, "a": .selectAll,
        "e": .showHidden, "i": .showDetails
    ]

    private static let byUSKeyCode: [UInt16: ShelfCommand] = [
        3: .search, 33: .previousCollection, 30: .nextCollection, 43: .settings, 45: .newCollection, 35: .pasteAll,
        40: .actions, 8: .copy, 1: .saveImage, 16: .quickLook, 0: .selectAll, 6: .undo, 14: .showHidden,
        34: .showDetails
    ]

    private static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    /// `shift` only changes two pairs: ⌘P pastes the selection at once and ⇧⌘P one clip at a time, ⌘Z undoes and ⇧⌘Z
    /// redoes. `option` moves the two bracket keys from collections to app chips (⌥⌘[ and ⌥⌘]) when the key itself is a
    /// bracket, and ⌥⌘← / ⌥⌘→ always step through app chips. When ⌥ was used to type `[` or `]` (as on German ⌥⌘5 /
    /// ⌥⌘6), the bracket switches collections instead of pasting a numbered clip.
    public static func resolve(
        characters: String?, keyCode: UInt16, shift: Bool = false, option: Bool = false,
        typedCharacters: String? = nil
    )
    -> ShelfCommand? {
        if keyCode == 36 { return .returnKey }
        if let arrow = arrowCommand(keyCode: keyCode, shift: shift, option: option) { return arrow }
        let base = characters?.lowercased()
        let typed = typedCharacters?.lowercased()
        if let bracket = bracketCommand(base: base, typed: typed, keyCode: keyCode, option: option) {
            return bracket
        }
        if let number = digitKeyCodes[keyCode] { return .pasteNth(number) }
        let command: ShelfCommand? = if let base, !base.isEmpty {
            byCharacter[base]
        } else {
            byUSKeyCode[keyCode]
        }

        return switch command {
        case .pasteAll where shift: .pasteOneByOne
        case .undo where shift: .redo
        case .previousCollection where option: .previousAppChip
        case .nextCollection where option: .nextAppChip
        default: command
        }
    }

    private static func arrowCommand(keyCode: UInt16, shift: Bool, option: Bool) -> ShelfCommand? {
        guard option, !shift else { return nil }
        return switch keyCode {
        case 123: .previousAppChip
        case 124: .nextAppChip
        default: nil
        }
    }

    private static func bracketCommand(
        base: String?, typed: String?, keyCode: UInt16, option: Bool
    )
    -> ShelfCommand? {
        let isDigitKey = digitKeyCodes[keyCode] != nil
        if typed == "[" || (option && isDigitKey && base == "[") {
            return option && base == "[" && !isDigitKey ? .previousAppChip : .previousCollection
        }
        if typed == "]" || (option && isDigitKey && base == "]") {
            return option && base == "]" && !isDigitKey ? .nextAppChip : .nextCollection
        }
        return nil
    }
}
