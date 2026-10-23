// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

extension Data {
    /// The SHA-256 digest as lowercase hex, the form stored as a clip's content hash.
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
