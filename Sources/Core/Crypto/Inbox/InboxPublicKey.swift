// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The inbox's public key as the app publishes it in the app group: anyone holding it can seal to the app, no one
/// can open with it.
public struct InboxPublicKey: Equatable, Sendable {
    public let rawRepresentation: Data

    private static let magic = Data("PESTOPUB".utf8)
    private static let version: UInt8 = 1

    public init(rawRepresentation: Data) throws {
        let raw = Data(rawRepresentation)
        _ = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
        self.rawRepresentation = raw
    }

    public init(_ key: Curve25519.KeyAgreement.PublicKey) {
        rawRepresentation = Data(key.rawRepresentation)
    }

    var agreementKey: Curve25519.KeyAgreement.PublicKey {
        get throws { try Curve25519.KeyAgreement.PublicKey(rawRepresentation: rawRepresentation) }
    }

    /// 16 bytes that name the key in every file sealed to it, so a file for an older key is known at once.
    public var keyID: Data {
        Data(SHA256.hash(data: Data("pesto.inbox.key.v1".utf8) + rawRepresentation).prefix(16))
    }

    public func serialized() -> Data {
        Self.magic + Data([Self.version]) + rawRepresentation
    }

    public static func parse(_ data: Data) throws -> InboxPublicKey {
        let bytes = Data(data)
        guard bytes.count == magic.count + 1 + 32, bytes.prefix(magic.count) == magic,
              bytes[magic.count] == version else { throw InboxError.damaged }
        do {
            return try InboxPublicKey(rawRepresentation: bytes.suffix(32))
        } catch {
            throw InboxError.damaged
        }
    }
}
