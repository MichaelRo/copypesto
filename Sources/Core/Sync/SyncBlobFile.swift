// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// A payload too big for a record, sealed into its own file `devices/<id>/blobs/<name>.pestoblob`. The name is a keyed
/// hash of the content, so the file's bytes are bound to it and a provider cannot tell which clip it is.
public enum SyncBlobFile {
    private static let magic = Data("PSTOBLOB".utf8)

    public static func fileName(_ blobName: String) -> String {
        "\(blobName).pestoblob"
    }

    private static func key(_ syncKey: SyncKey, name: String) -> SymmetricKey {
        syncKey.subkey(salt: Data(name.utf8), info: "pesto.sync.blob.v1")
    }

    public static func seal(_ payload: Data, name: String, syncKey: SyncKey) throws -> Data {
        let box = try AES.GCM.seal(payload, using: key(syncKey, name: name), authenticating: magic + Data(name.utf8))
        guard let combined = box.combined else { throw SyncError.malformed("blob") }
        return magic + combined
    }

    /// Opens a blob and checks it is the content its name says it is.
    public static func open(_ data: Data, name: String, syncKey: SyncKey) throws -> Data {
        guard data.count > magic.count, data.prefix(magic.count) == magic else { throw SyncError.malformed("blob") }
        let plain: Data
        do {
            plain = try AES.GCM.open(
                AES.GCM.SealedBox(combined: Data(data.dropFirst(magic.count))), using: key(syncKey, name: name),
                authenticating: magic + Data(name.utf8)
            )
        } catch {
            throw SyncError.wrongKey
        }
        guard syncKey.blobName(plainHash: Data(SHA256.hash(data: plain)).hexString) == name else {
            throw SyncError.malformed("blob does not match its name")
        }
        return plain
    }
}
