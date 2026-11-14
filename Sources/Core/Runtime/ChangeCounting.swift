// SPDX-License-Identifier: MIT
import Foundation

/// The part of a pasteboard `OwnWriteGate` needs. `NSPasteboard` is not `Sendable` and does not claim to be; code that
/// reads from several threads goes through `SystemPasteboard`.
public protocol ChangeCounting {
    var changeCount: Int { get }
}
