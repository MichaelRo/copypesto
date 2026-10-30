// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The 256-bit key that opens a sync folder. It is separate from the key that seals this Mac's own history (ADR 0002)
/// and it never opens anything outside the sync folder.
public struct SyncKey: Equatable, Sendable {
    public let data: Data

    public init(data: Data) throws {
        guard data.count == 32 else { throw SyncError.malformed("sync key length") }
        self.data = data
    }

    public static func generate() -> SyncKey {
        SyncKey(unchecked: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    private init(unchecked data: Data) {
        self.data = data
    }

    var symmetric: SymmetricKey {
        SymmetricKey(data: data)
    }

    func subkey(salt: Data, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: symmetric, salt: salt, info: Data(info.utf8), outputByteCount: 32
        )
    }

    func mac(_ label: String, _ parts: Data...) -> Data {
        var hmac = HMAC<SHA256>(key: symmetric)
        hmac.update(data: Data(label.utf8))
        for part in parts {
            hmac.update(data: part)
        }
        return Data(hmac.finalize())
    }

    /// The name of an external payload file: keyed, so a provider cannot tell which clip is which.
    public func blobName(plainHash: String) -> String {
        let key = subkey(salt: Data(), info: "pesto.sync.blobname.v1")
        return Data(HMAC<SHA256>.authenticationCode(for: Data(plainHash.utf8), using: key)).hexString
    }

    // MARK: Recovery key

    /// Base32 with a two-byte checksum, in groups of four, as the backup's recovery key reads.
    public var recoveryKey: String {
        let checksum = Data(SHA256.hash(data: data).prefix(2))
        let text = SyncBase32.encode(data + checksum)
        return stride(from: 0, to: text.count, by: 4).map { index in
            let start = text.index(text.startIndex, offsetBy: index)
            return String(text[start..<text.index(start, offsetBy: min(4, text.count - index))])
        }.joined(separator: "-")
    }

    public init(recoveryKey: String) throws {
        let cleaned = recoveryKey.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard let decoded = SyncBase32.decode(cleaned), decoded.count == 34 else {
            throw SyncError.malformed("recovery key")
        }
        let key = decoded.prefix(32)
        guard Data(SHA256.hash(data: key).prefix(2)) == decoded.suffix(2) else {
            throw SyncError.malformed("recovery key checksum")
        }
        try self.init(data: Data(key))
    }
}

enum SyncBase32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ data: Data) -> String {
        var out = ""
        var buffer: UInt32 = 0
        var bits = 0
        for byte in data {
            buffer = buffer << 8 | UInt32(byte)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[Int(buffer >> UInt32(bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 { out.append(alphabet[Int(buffer << UInt32(5 - bits)) & 31]) }
        return out
    }

    static func decode(_ text: String) -> Data? {
        var out = Data()
        var buffer: UInt32 = 0
        var bits = 0
        for character in text {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = buffer << 5 | UInt32(value)
            bits += 5
            if bits >= 8 {
                out.append(UInt8((buffer >> UInt32(bits - 8)) & 255))
                bits -= 8
            }
        }
        return out
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
