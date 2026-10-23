// SPDX-License-Identifier: MIT
import Foundation

/// A small file the app keeps only for speed, sealed like the store: AES-GCM under the install's key, bound to the
/// file's name so a copy under another name does not open. Anything that does not open, including the plaintext an
/// older version wrote, reads as nothing and is removed.
public struct SealedFile: Sendable {
    public let url: URL
    private let encryption: BlobEncryption

    private struct Sealed: Codable {
        let nonce: Data
        let ciphertext: Data
    }

    public init(url: URL, encryption: BlobEncryption = BlobEncryption()) {
        self.url = url
        self.encryption = encryption
    }

    private var associatedData: Data {
        Data("pesto.sealed-file:\(url.lastPathComponent)".utf8)
    }

    public func write(_ plaintext: Data) throws {
        let envelope = try encryption.encrypt(plaintext, associatedData: associatedData)
        let data = try JSONEncoder().encode(Sealed(nonce: envelope.nonce, ciphertext: envelope.ciphertext))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try PrivateFile.write(data, to: url)
    }

    public func read() -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let sealed = try? JSONDecoder().decode(Sealed.self, from: data),
              let plaintext = try? encryption.decrypt(
                  BlobEncryption.EncryptedEnvelope(ciphertext: sealed.ciphertext, nonce: sealed.nonce),
                  associatedData: associatedData
              ) else
        {
            remove()
            return nil
        }
        return plaintext
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
