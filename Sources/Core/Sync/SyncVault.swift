// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// `vault-<epoch>.pestosync`: written once by the Mac that makes the sync group (or that resets it), never rewritten.
/// It
/// names the group (a random vault id) and its epoch, holds a check value of the sync key so a Mac can tell it has the
/// right key without anything in the folder opening, and is signed by its creator, so two resets that race resolve to
/// the one an enrolled device made.
public struct SyncVault: Equatable, Sendable {
    public static let magic = Data("PSTOSYNC".utf8)
    public static let version: UInt16 = 1

    public let vaultID: Data
    public let epoch: UInt32
    public let checkValue: Data
    public let creator: SyncDevicePublicKeys

    public static func fileName(epoch: UInt32) -> String {
        "vault-\(epoch).pestosync"
    }

    public static func create(
        vaultID: Data = Data((0..<16).map { _ in UInt8.random(in: 0...255) }),
        epoch: UInt32 = 1, syncKey: SyncKey, creator: SyncDeviceKeys
    )
        -> SyncVault
    {
        SyncVault(
            vaultID: vaultID, epoch: epoch, checkValue: syncKey.mac("pesto.sync.check.v1", vaultID, epochBytes(epoch)),
            creator: creator.publicKeys
        )
    }

    public func serialized(signedBy keys: SyncDeviceKeys) throws -> Data {
        let body = bodyBytes
        return try body + keys.signing.signature(for: body)
    }

    private var bodyBytes: Data {
        var out = Self.magic
        out.appendBigEndian(Self.version)
        out.append(vaultID)
        out.appendBigEndian(epoch)
        out.append(checkValue)
        out.append(creator.signing)
        out.append(creator.agreement)
        return out
    }

    /// Reads a vault file and checks its signature against the key it names; the caller decides whether that creator
    /// is one it trusts.
    public static func parse(_ data: Data) throws -> SyncVault {
        var reader = ByteReader(data)
        guard try reader.bytes(magic.count) == magic else { throw SyncError.malformed("not a vault") }
        guard try UInt16(reader.bytes(2).reduce(0) { $0 << 8 | Int($1) }) == version else {
            throw SyncError.unsupportedVersion
        }
        let vaultID = try reader.bytes(16)
        let epoch = try reader.u32()
        let check = try reader.bytes(32)
        let creator = try SyncDevicePublicKeys(signing: reader.bytes(32), agreement: reader.bytes(32))
        let signature = try reader.bytes(64)
        guard reader.isAtEnd else { throw SyncError.malformed("trailing bytes") }
        let vault = SyncVault(vaultID: vaultID, epoch: epoch, checkValue: check, creator: creator)
        guard let key = try? creator.signingKey(), key.isValidSignature(signature, for: vault.bodyBytes) else {
            throw SyncError.badSignature
        }
        return vault
    }

    public func accepts(_ key: SyncKey) -> Bool {
        key.mac("pesto.sync.check.v1", vaultID, Self.epochBytes(epoch)) == checkValue
    }

    private static func epochBytes(_ epoch: UInt32) -> Data {
        var out = Data()
        out.appendBigEndian(epoch)
        return out
    }
}
