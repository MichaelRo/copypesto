// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// What one Mac signs with and is paired with. The private halves never leave this Mac; the public halves go in its
/// device record so the others can check its signatures and seal a key to it.
public struct SyncDeviceKeys: Sendable {
    public let signing: Curve25519.Signing.PrivateKey
    public let agreement: Curve25519.KeyAgreement.PrivateKey

    public init(signing: Curve25519.Signing.PrivateKey, agreement: Curve25519.KeyAgreement.PrivateKey) {
        self.signing = signing
        self.agreement = agreement
    }

    public static func generate() -> SyncDeviceKeys {
        SyncDeviceKeys(signing: Curve25519.Signing.PrivateKey(), agreement: Curve25519.KeyAgreement.PrivateKey())
    }

    public var publicKeys: SyncDevicePublicKeys {
        SyncDevicePublicKeys(
            signing: signing.publicKey.rawRepresentation, agreement: agreement.publicKey.rawRepresentation
        )
    }

    /// 64 bytes, for the this-device Keychain item.
    public var rawRepresentation: Data {
        signing.rawRepresentation + agreement.rawRepresentation
    }

    public init(rawRepresentation: Data) throws {
        guard rawRepresentation.count == 64 else { throw SyncError.malformed("device keys") }
        signing = try Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation.prefix(32))
        agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawRepresentation.suffix(32))
    }
}

public struct SyncDevicePublicKeys: Codable, Equatable, Sendable {
    public var signing: Data
    public var agreement: Data

    public init(signing: Data, agreement: Data) {
        self.signing = signing
        self.agreement = agreement
    }

    /// Names a signer in a manifest without carrying the key.
    public var keyID: String {
        Data(SHA256.hash(data: signing)).hexString
    }

    public func signingKey() throws -> Curve25519.Signing.PublicKey {
        try Curve25519.Signing.PublicKey(rawRepresentation: signing)
    }
}

/// The signers a Mac accepts: the devices enrolled in the sync group, by key id.
public struct SyncTrust: Sendable, Equatable {
    public var signers: [String: SyncDevicePublicKeys]

    public init(_ keys: [SyncDevicePublicKeys] = []) {
        signers = Dictionary(uniqueKeysWithValues: keys.map { ($0.keyID, $0) })
    }

    public mutating func add(_ keys: SyncDevicePublicKeys) {
        signers[keys.keyID] = keys
    }

    func verify(_ signature: Data, over message: Data, signerID: String) throws {
        guard let keys = signers[signerID], let key = try? keys.signingKey() else { throw SyncError.unknownSigner }
        guard key.isValidSignature(signature, for: message) else { throw SyncError.badSignature }
    }
}
