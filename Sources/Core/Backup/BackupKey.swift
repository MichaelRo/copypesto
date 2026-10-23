// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

public enum BackupError: Error, Equatable, Sendable {
    case notABackup
    case unsupportedVersion(Int)
    case wrongCredential
    case corrupted
    case malformedRecoveryKey
}

/// The random 256-bit key every backup is encrypted under. It is never stored with a backup in the clear: each file
/// carries it wrapped by the user's passphrase, and the user can keep `recoveryKey` as the alternative.
public struct BackupKey: Sendable, Equatable {
    public static let byteCount = 32

    let symmetricKey: SymmetricKey

    public init(symmetricKey: SymmetricKey) {
        self.symmetricKey = symmetricKey
    }

    public static func generate() -> BackupKey {
        BackupKey(symmetricKey: SymmetricKey(size: .bits256))
    }

    public var bytes: Data {
        symmetricKey.withUnsafeBytes { Data($0) }
    }

    /// 32 key bytes and a 2-byte checksum, base32, in dash-separated groups of four so it can be written down and a
    /// typo is caught before any decryption is attempted.
    public var recoveryKey: String {
        let payload = bytes
        let checksum = Data(SHA256.hash(data: payload).prefix(2))
        let characters = Array(Base32.encode(payload + checksum))
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: "-")
    }

    public init(recoveryKey: String) throws {
        let cleaned = recoveryKey.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard let decoded = Base32.decode(cleaned), decoded.count == Self.byteCount + 2 else {
            throw BackupError.malformedRecoveryKey
        }
        let payload = decoded.prefix(Self.byteCount)
        guard Data(SHA256.hash(data: payload).prefix(2)) == decoded.suffix(2) else {
            throw BackupError.malformedRecoveryKey
        }
        self.init(symmetricKey: SymmetricKey(data: payload))
    }

    public static func == (lhs: BackupKey, rhs: BackupKey) -> Bool {
        lhs.bytes == rhs.bytes
    }
}

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ data: Data) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return output
    }

    static func decode(_ text: String) -> Data? {
        var output = Data()
        var buffer = 0
        var bits = 0
        for character in text {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                output.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
            buffer &= (1 << bits) - 1
        }
        return output
    }
}

enum SymmetricKeyData {
    static func key(from data: Data) -> SymmetricKey {
        SymmetricKey(data: data)
    }
}
