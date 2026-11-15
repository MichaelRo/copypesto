// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// A sealed app-group file: the format's magic and version, then the JSON value sealed with AES-GCM-256 (nonce,
/// ciphertext, tag). The header and the purpose string are the associated data, so a file of another purpose or
/// version, or a changed byte anywhere, does not open.
public enum SealedFileEnvelope {
    private static let sealedOverhead = 12 + 16

    public static func seal(_ value: some Encodable, as format: SealedFileFormat, with key: SymmetricKey) throws
    -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let plaintext = try encoder.encode(value)
        guard plaintext.count + format.header.count + sealedOverhead <= format.maxFileBytes else {
            throw SealedFileError.tooLarge
        }
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: format.header + format.purpose)
        guard let combined = sealed.combined else { throw SealedFileError.damaged }
        return format.header + Data(combined)
    }

    public static func open<Value: Decodable>(
        _: Value.Type, from data: Data, as format: SealedFileFormat, with key: SymmetricKey
    ) throws
    -> Value {
        let bytes = Data(data)
        let header = format.header
        guard bytes.count > header.count + sealedOverhead, bytes.prefix(header.count) == header else {
            throw SealedFileError.damaged
        }
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: bytes.subdata(in: header.count..<bytes.count))
            plaintext = try AES.GCM.open(box, using: key, authenticating: header + format.purpose)
        } catch {
            throw SealedFileError.wrongKey
        }
        do {
            return try JSONDecoder().decode(Value.self, from: plaintext)
        } catch {
            throw SealedFileError.damaged
        }
    }
}
