// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The last chunk of a segment: who wrote it, which records it holds, a digest of the chunks before it, the hash of the
/// manifest of the segment before it (a chain per device) and a signature by the device, so one Mac cannot forge
/// another's records and a provider cannot reorder, drop or replay a segment unnoticed.
public struct SyncManifest: Codable, Equatable, Sendable {
    public static let zeroHash = String(repeating: "0", count: 64)

    public var version = 1
    public var vaultID: String
    public var deviceID: String
    public var epoch: UInt32
    public var firstSequence: UInt64
    public var lastSequence: UInt64
    public var recordCount: Int
    public var bodyDigest: String
    public var previousManifestHash: String
    public var createdAt: Date
    public var signerKeyID: String
    public var snapshot: Bool?
    public var signature: String = ""

    public func signingBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = ""
        return try Self.canonical(unsigned)
    }

    public func hash() throws -> String {
        try Data(SHA256.hash(data: Self.canonical(self))).hexString
    }

    func signed(by keys: SyncDeviceKeys) throws -> SyncManifest {
        var copy = self
        copy.signature = try keys.signing.signature(for: signingBytes()).base64EncodedString()
        return copy
    }

    func verify(trust: SyncTrust) throws {
        guard let signature = Data(base64Encoded: signature) else { throw SyncError.badSignature }
        try trust.verify(signature, over: signingBytes(), signerID: signerKeyID)
    }

    static func canonical(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    static func decode(_ data: Data) throws -> SyncManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(SyncManifest.self, from: data)
    }
}
