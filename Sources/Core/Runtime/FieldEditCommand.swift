// SPDX-License-Identifier: MIT
import Foundation

public enum FieldEditCommand: Equatable, Sendable {
    case cut
    case copy
    case paste
    case undo
    case redo

    private static let byCharacter: [String: FieldEditCommand] = ["x": .cut, "c": .copy, "v": .paste, "z": .undo]
    private static let byUSKeyCode: [UInt16: FieldEditCommand] = [7: .cut, 8: .copy, 9: .paste, 6: .undo]

    /// Matched like `ShelfCommand`: by the character the key prints, with the US key code as the fallback. Shift only
    /// turns ⌘Z into redo; ⇧⌘X, ⇧⌘C and ⇧⌘V are not Edit commands.
    public static func resolve(characters: String?, keyCode: UInt16, shift: Bool) -> FieldEditCommand? {
        let command: FieldEditCommand? = if let characters, !characters.isEmpty {
            byCharacter[characters.lowercased()]
        } else {
            byUSKeyCode[keyCode]
        }
        guard shift else { return command }
        return command == .undo ? .redo : nil
    }
}
