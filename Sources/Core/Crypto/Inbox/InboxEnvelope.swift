// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// One inbox file: `PESTOINB`, a version byte, the recipient key's id (16 bytes) and HPKE's encapsulated key (32
/// bytes), then the item sealed with HPKE (X25519, SHA-256, ChaChaPoly) to the app's inbox key. The whole header is
/// the associated data, so a changed byte anywhere does not open.
public enum InboxEnvelope {
    private static let magic = Data("PESTOINB".utf8)
    private static let version: UInt8 = 1
    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    private static let info = Data("pesto.inbox.v1".utf8)
    private static var headerLength: Int {
        magic.count + 1 + 16 + 32
    }

    public static func seal(_ item: InboxItem, to key: InboxPublicKey) throws -> Data {
        let plaintext = try item.validated().plaintext()
        var sender = try HPKE.Sender(recipientKey: key.agreementKey, ciphersuite: suite, info: info)
        let encapsulated = Data(sender.encapsulatedKey)
        guard encapsulated.count == 32 else { throw InboxError.damaged }
        let header = magic + Data([version]) + key.keyID + encapsulated
        return try header + Data(sender.seal(plaintext, authenticating: header))
    }

    public static func open(_ data: Data, with privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> InboxItem {
        let bytes = Data(data)
        guard bytes.count > headerLength + 16, bytes.prefix(magic.count) == magic, bytes[magic.count] == version else {
            throw InboxError.damaged
        }
        let header = bytes.prefix(headerLength)
        let keyID = bytes.subdata(in: (magic.count + 1)..<(magic.count + 17))
        guard keyID == InboxPublicKey(privateKey.publicKey).keyID else { throw InboxError.wrongKey }
        let encapsulated = bytes.subdata(in: (magic.count + 17)..<headerLength)
        let plaintext: Data
        do {
            var recipient = try HPKE.Recipient(
                privateKey: privateKey, ciphersuite: suite, info: info, encapsulatedKey: encapsulated
            )
            plaintext = try recipient.open(bytes.subdata(in: headerLength..<bytes.count), authenticating: Data(header))
        } catch {
            throw InboxError.wrongKey
        }
        return try InboxItem.parse(plaintext: plaintext).validated()
    }
}
