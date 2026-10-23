// SPDX-License-Identifier: MIT
import Foundation

public extension Data {
    /// Returns `true` when the first 6 bytes match a GIF magic header (GIF87a or GIF89a).
    /// Thread-safe — reads raw bytes without creating any AppKit objects.
    var isGIF: Bool {
        let gif87a: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61] // GIF87a
        let gif89a: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61] // GIF89a
        let header = Array(prefix(6))
        return header == gif87a || header == gif89a
    }
}
