// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// `devices/<id>/device.pestodev`: who a Mac is in the group (its name, the public halves of its keys), sealed under
/// the
/// sync key and signed by the Mac itself. Holding the sync key is membership; this record is how the others learn which
/// signatures to trust. It is rewritten whenever the epoch changes.
public struct SyncDeviceRecord: Codable, Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var keys: SyncDevicePublicKeys
    public var epoch: UInt32
    public var createdAt: Date
    public var signature: String = ""

    public init(deviceID: String, name: String, keys: SyncDevicePublicKeys, epoch: UInt32, createdAt: Date) {
        self.deviceID = deviceID
        self.name = name
        self.keys = keys
        self.epoch = epoch
        self.createdAt = createdAt
    }

    private static let magic = Data("PSTODEV1".utf8)

    private func signingBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = ""
        return try SyncManifest.canonical(unsigned)
    }

    private static func key(_ syncKey: SyncKey, vaultID: Data) -> SymmetricKey {
        syncKey.subkey(salt: vaultID, info: "pesto.sync.device.v1")
    }

    private static func associatedData(vaultID: Data, epoch: UInt32, deviceID: String) -> Data {
        var out = magic + vaultID
        out.appendBigEndian(epoch)
        out.append(Data(deviceID.utf8))
        return out
    }

    public func sealed(syncKey: SyncKey, vaultID: Data, signedBy device: SyncDeviceKeys) throws -> Data {
        var copy = self
        copy.signature = try device.signing.signature(for: signingBytes()).base64EncodedString()
        let box = try AES.GCM.seal(
            SyncManifest.canonical(copy), using: Self.key(syncKey, vaultID: vaultID),
            authenticating: Self.associatedData(vaultID: vaultID, epoch: epoch, deviceID: deviceID)
        )
        guard let combined = box.combined else { throw SyncError.malformed("device record") }
        return Self.magic + combined
    }

    public static func open(
        _ data: Data, syncKey: SyncKey, vaultID: Data, epoch: UInt32, deviceID: String
    ) throws
    -> SyncDeviceRecord {
        guard data.count > magic.count,
              data.prefix(magic.count) == magic else { throw SyncError.malformed("device record") }
        let plain: Data
        do {
            plain = try AES.GCM.open(
                AES.GCM.SealedBox(combined: Data(data.dropFirst(magic.count))), using: key(syncKey, vaultID: vaultID),
                authenticating: associatedData(vaultID: vaultID, epoch: epoch, deviceID: deviceID)
            )
        } catch {
            throw SyncError.wrongKey
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let record = try decoder.decode(SyncDeviceRecord.self, from: plain)
        guard record.deviceID == deviceID, record.epoch == epoch, let signature = Data(base64Encoded: record.signature),
              let signer = try? record.keys.signingKey(),
              try signer.isValidSignature(signature, for: record.signingBytes()) else { throw SyncError.badSignature }
        return record
    }
}
