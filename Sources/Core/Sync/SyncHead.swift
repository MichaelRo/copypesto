// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// `head.pestohead`: the one file a Mac rewrites. It says how far this Mac's log goes (its last sequence and the hash
/// of
/// its last manifest) and how far it has read every other Mac, which is what lets old segments be compacted. Sealed
/// under
/// the sync key and signed, so a provider can neither read the cursors nor put back an old head unnoticed.
public struct SyncHead: Codable, Equatable, Sendable {
    public var deviceID: String
    public var epoch: UInt32
    public var lastSequence: UInt64
    public var lastManifestHash: String
    public var cursors: [String: UInt64]
    public var writtenAt: Date
    public var signerKeyID: String
    public var signature: String = ""

    public init(
        deviceID: String, epoch: UInt32, lastSequence: UInt64, lastManifestHash: String,
        cursors: [String: UInt64], writtenAt: Date, signerKeyID: String
    ) {
        self.deviceID = deviceID
        self.epoch = epoch
        self.lastSequence = lastSequence
        self.lastManifestHash = lastManifestHash
        self.cursors = cursors
        self.writtenAt = writtenAt
        self.signerKeyID = signerKeyID
    }

    private static let magic = Data("PSTOHEAD".utf8)

    private func signingBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = ""
        return try SyncManifest.canonical(unsigned)
    }

    private static func key(_ syncKey: SyncKey, deviceID: String) -> SymmetricKey {
        syncKey.subkey(salt: Data(deviceID.utf8), info: "pesto.sync.head.v1")
    }

    private static func associatedData(deviceID: String, epoch: UInt32) -> Data {
        var out = magic + Data(deviceID.utf8)
        out.appendBigEndian(epoch)
        return out
    }

    public func sealed(syncKey: SyncKey, signedBy keys: SyncDeviceKeys) throws -> Data {
        var copy = self
        copy.signature = try keys.signing.signature(for: signingBytes()).base64EncodedString()
        let box = try AES.GCM.seal(
            SyncManifest.canonical(copy), using: Self.key(syncKey, deviceID: deviceID),
            authenticating: Self.associatedData(deviceID: deviceID, epoch: epoch)
        )
        guard let combined = box.combined else { throw SyncError.malformed("head") }
        return Self.magic + combined
    }

    /// Opens a head written by `deviceID` for `epoch`.
    public static func open(
        _ data: Data, syncKey: SyncKey, trust: SyncTrust, deviceID: String, epoch: UInt32
    ) throws
    -> SyncHead {
        guard data.count > magic.count,
              data.prefix(magic.count) == magic else { throw SyncError.malformed("not a head") }
        let plain: Data
        do {
            plain = try AES.GCM.open(
                AES.GCM.SealedBox(combined: data.dropFirst(magic.count)),
                using: key(syncKey, deviceID: deviceID), authenticating: associatedData(
                    deviceID: deviceID,
                    epoch: epoch
                )
            )
        } catch {
            throw SyncError.wrongKey
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let head = try decoder.decode(SyncHead.self, from: plain)
        guard head.deviceID == deviceID, head.epoch == epoch, let signature = Data(base64Encoded: head.signature) else {
            throw SyncError.malformed("head fields")
        }
        try trust.verify(signature, over: head.signingBytes(), signerID: head.signerKeyID)
        return head
    }
}
