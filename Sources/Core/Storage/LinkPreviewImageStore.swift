// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// Link preview images, one encrypted file per item. They used to live in a column on every history item, which put
/// about 37 MB of plaintext image data in memory for 5,000 items and in the store unencrypted.
public struct LinkPreviewImageStore: Sendable {
    private let directory: URL
    private let key: @Sendable () throws -> SymmetricKey

    public init(
        directory: URL = AppPaths.supportDirectory.appendingPathComponent("link-previews", isDirectory: true),
        key: @escaping @Sendable () throws -> SymmetricKey = { try BlobEncryption().loadOrCreateKey() }
    ) {
        self.directory = directory
        self.key = key
    }

    public func save(_ image: Data, for id: UUID) throws {
        let sealed = try AES.GCM.seal(image, using: key(), authenticating: Data(id.uuidString.utf8))
        guard let combined = sealed.combined else { throw BlobEncryption.Error.invalidNonce }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PrivateFile.write(combined, to: fileURL(for: id))
    }

    public func load(for id: UUID) -> Data? {
        guard let combined = try? Data(contentsOf: fileURL(for: id)),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let key = try? key() else { return nil }
        return try? AES.GCM.open(box, using: key, authenticating: Data(id.uuidString.utf8))
    }

    /// The file as it is on disk, still sealed, so an undo can keep it without ever opening it.
    func sealedFile(for id: UUID) -> Data? {
        try? Data(contentsOf: fileURL(for: id))
    }

    func restoreSealedFile(_ file: Data, for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PrivateFile.write(file, to: fileURL(for: id))
    }

    public func delete(ids: [UUID]) {
        ids.forEach { try? FileManager.default.removeItem(at: fileURL(for: $0)) }
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("bin")
    }
}
