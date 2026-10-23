// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox

extension NSEvent.ModifierFlags {
    /// The Carbon mask the global shortcuts are stored and registered with.
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if contains(.command) { carbon |= UInt32(cmdKey) }
        if contains(.shift) { carbon |= UInt32(shiftKey) }
        if contains(.option) { carbon |= UInt32(optionKey) }
        if contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    init(carbon: UInt32) {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        self = flags
    }
}
