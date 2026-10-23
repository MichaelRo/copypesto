// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Finds the key code that types a character under the user's keyboard layout. Key codes are physical positions,
/// so the ANSI `V` position (0x09) is `K` on Dvorak and `.` on some other layouts.
public enum KeyboardLayoutKeyCode {
    static let keyCodeRange: Range<CGKeyCode> = 0..<128

    /// The first key code whose translation is `character`; nil if the layout has no such key.
    static func keyCode(for character: Character, translating translate: (CGKeyCode) -> String?) -> CGKeyCode? {
        keyCodeRange.first { translate($0)?.lowercased() == String(character).lowercased() }
    }

    /// Uses the ASCII-capable layout so a Cyrillic or Arabic layout still finds the Latin `V` that ⌘V is bound to.
    /// Must run on the main thread (Text Services Manager).
    public static func current(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = UInt32(LMGetKbdType())
        let commandState = UInt32((cmdKey >> 8) & 0xFF)

        return keyCode(for: character) { code in
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                UInt16(code),
                UInt16(kUCKeyActionDown),
                commandState,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
