// SPDX-License-Identifier: MIT
import Foundation

/// What a string costs in a sealed app-group file, which is JSON before it is sealed: a control character takes six
/// bytes there, and one character can be any number of bytes, so neither UTF-8 length nor a character count bounds it.
enum EncodedText {
    /// The longest UTF-8 encoding of one scalar.
    private static let maxBytesPerCharacter = 4

    /// The bytes `JSONEncoder` writes between the quotes, with slashes left unescaped as `SealedFileEnvelope` does.
    static func bytes(_ text: String) -> Int {
        bytes(utf8: text.utf8)
    }

    /// At most `maxCharacters` whole characters, costing at most four bytes for each of them: ordinary text keeps its
    /// full length, and text of escaped or very long characters is cut shorter.
    static func prefix(_ text: String, maxCharacters: Int) -> String {
        var room = maxCharacters * maxBytesPerCharacter
        return String(text.prefix(maxCharacters).prefix { character in
            room -= bytes(utf8: character.utf8)
            return room >= 0
        })
    }

    private static func bytes(utf8: some Sequence<UInt8>) -> Int {
        utf8.reduce(0) { total, byte in
            switch byte {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"), 0x08, 0x09, 0x0A, 0x0C, 0x0D: total + 2
            case ..<0x20: total + 6
            default: total + 1
            }
        }
    }
}
