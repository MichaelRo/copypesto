// SPDX-License-Identifier: MIT

/// A global shortcut as it is set now, for checking a new one against.
public struct NamedHotkey: Equatable, Sendable {
    public let name: String
    public let keyCode: Int
    public let modifiers: UInt32

    public init(name: String, keyCode: Int, modifiers: UInt32) {
        self.name = name
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
