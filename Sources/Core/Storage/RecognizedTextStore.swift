// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The whole text Vision read in a picture, one sealed file per clip (ADR 0034). The clip's own preview keeps only the
/// first 500 characters, and the text is too big for a column: every `@Query` loads every column of every clip.
public struct RecognizedTextStore: Sendable {
    private let directory: URL
    private let key: @Sendable () throws -> SymmetricKey

    public init(
        directory: URL = AppPaths.supportDirectory.appendingPathComponent("recognized-text", isDirectory: true),
        key: @escaping @Sendable () throws -> SymmetricKey = { try BlobEncryption().loadOrCreateKey() }
    ) {
        self.directory = directory
        self.key = key
    }

    public func save(_ text: String, for id: UUID) throws {
        let sealed = try AES.GCM.seal(Data(text.utf8), using: key(), authenticating: Self.associatedData(for: id))
        guard let combined = sealed.combined else { throw BlobEncryption.Error.invalidNonce }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PrivateFile.write(combined, to: fileURL(for: id))
    }

    public func load(for id: UUID) -> String? {
        guard let combined = try? Data(contentsOf: fileURL(for: id)),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let key = try? key() else { return nil }
        let aad = Self.associatedData(for: id)
        return (try? AES.GCM.open(box, using: key, authenticating: aad)).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    /// Whether a text is stored for the clip, without opening it: the menu asks this when it opens.
    public func exists(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
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

    /// Bound to the clip and to this kind of file, so a link preview image moved here does not open either.
    private static func associatedData(for id: UUID) -> Data {
        Data("pesto.v2|\(id.uuidString)|recognized-text".utf8)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("bin")
    }
}
