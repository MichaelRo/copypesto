// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The quick-insert file (ADR 0051): `PESTOQIS`, a version byte, then the set sealed with AES-GCM-256 under the shared
/// quick-insert key (nonce, ciphertext, tag). The header and the purpose string are the associated data, so a file
/// of another purpose or version, or a changed byte anywhere, does not open.
public enum QuickInsertEnvelope {
    private static let magic = Data("PESTOQIS".utf8)
    private static let version: UInt8 = 1
    private static let purpose = Data("pesto.quick-insert.v1".utf8)
    private static let sealedOverhead = 12 + 16

    private static var header: Data {
        magic + Data([version])
    }

    public static func seal(_ set: QuickInsertSet, with key: SymmetricKey) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let plaintext = try encoder.encode(set)
        guard plaintext.count + header.count + sealedOverhead <= QuickInsertPolicy.maxFileBytes else {
            throw QuickInsertError.tooLarge
        }
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header + purpose)
        guard let combined = sealed.combined else { throw QuickInsertError.damaged }
        return header + Data(combined)
    }

    public static func open(_ data: Data, with key: SymmetricKey) throws -> QuickInsertSet {
        let bytes = Data(data)
        guard bytes.count > header.count + sealedOverhead, bytes.prefix(header.count) == header else {
            throw QuickInsertError.damaged
        }
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: bytes.subdata(in: header.count..<bytes.count))
            plaintext = try AES.GCM.open(box, using: key, authenticating: header + purpose)
        } catch {
            throw QuickInsertError.wrongKey
        }
        do {
            return try JSONDecoder().decode(QuickInsertSet.self, from: plaintext)
        } catch {
            throw QuickInsertError.damaged
        }
    }
}
