// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// `devices/<id>/join.pestojoin`: a new Mac says it wants to join (interim mode, ADR 0018). It carries only public
/// keys,
/// signed by the new Mac, and it is readable by anyone with the folder; what protects the join is the six words both
/// Macs show (`SyncPairingCode`), which a provider that swapped a key could not make match.
public struct SyncJoinRequest: Codable, Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var keys: SyncDevicePublicKeys
    public var vaultID: String
    public var createdAt: Date
    public var signature: String = ""

    public init(deviceID: String, name: String, keys: SyncDevicePublicKeys, vaultID: Data, createdAt: Date) {
        self.deviceID = deviceID
        self.name = name
        self.keys = keys
        self.vaultID = vaultID.hexString
        self.createdAt = createdAt
    }

    private func signingBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = ""
        return try SyncManifest.canonical(unsigned)
    }

    public func signed(by device: SyncDeviceKeys) throws -> SyncJoinRequest {
        var copy = self
        copy.signature = try device.signing.signature(for: signingBytes()).base64EncodedString()
        return copy
    }

    public func serialized() throws -> Data {
        try SyncManifest.canonical(self)
    }

    public static func parse(_ data: Data) throws -> SyncJoinRequest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let request = try decoder.decode(SyncJoinRequest.self, from: data)
        guard let signature = Data(base64Encoded: request.signature), let signer = try? request.keys.signingKey(),
              try signer.isValidSignature(signature, for: request.signingBytes()) else { throw SyncError.badSignature }
        return request
    }

    /// The words the approving Mac and the joining Mac must see the same.
    public func pairingWords(approver: SyncDevicePublicKeys) -> [String] {
        let vault = Data(hexString: vaultID) ?? Data()
        return SyncPairingCode.words(
            vaultID: vault, keyA: keys.signing + keys.agreement, keyB: approver.signing + approver.agreement
        )
    }
}

/// `devices/<approver>/grants/<new id>.pestogrant`: the sync key, sealed to the joining Mac's key with HPKE, and signed
/// by the approving Mac. Only the joining Mac can open it.
public struct SyncGrant: Codable, Equatable, Sendable {
    public var vaultID: String
    public var epoch: UInt32
    public var forDeviceID: String
    public var approver: SyncDevicePublicKeys
    public var encapsulatedKey: Data
    public var sealedKey: Data
    public var signature: String = ""

    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    private static func context(vaultID: Data, epoch: UInt32, deviceID: String) -> Data {
        var out = Data("pesto.sync.grant.v1".utf8) + vaultID
        out.appendBigEndian(epoch)
        out.append(Data(deviceID.utf8))
        return out
    }

    private func signingBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = ""
        return try SyncManifest.canonical(unsigned)
    }

    public static func seal(
        key: SyncKey, vaultID: Data, epoch: UInt32, to request: SyncJoinRequest, approver: SyncDeviceKeys
    ) throws
    -> SyncGrant {
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: request.keys.agreement)
        let context = context(vaultID: vaultID, epoch: epoch, deviceID: request.deviceID)
        var sender = try HPKE.Sender(recipientKey: recipient, ciphersuite: suite, info: context)
        let sealed = try sender.seal(key.data, authenticating: context)
        var grant = SyncGrant(
            vaultID: vaultID.hexString, epoch: epoch, forDeviceID: request.deviceID,
            approver: approver.publicKeys, encapsulatedKey: Data(sender.encapsulatedKey), sealedKey: Data(sealed)
        )
        grant.signature = try approver.signing.signature(for: grant.signingBytes()).base64EncodedString()
        return grant
    }

    public func serialized() throws -> Data {
        try SyncManifest.canonical(self)
    }

    public static func parse(_ data: Data) throws -> SyncGrant {
        try JSONDecoder().decode(SyncGrant.self, from: data)
    }

    /// The words the joining Mac shows for this grant, to be compared with the approving Mac's screen.
    public func pairingWords(for request: SyncJoinRequest) -> [String] {
        request.pairingWords(approver: approver)
    }

    /// Opens a grant addressed to this Mac, once the person has confirmed the six words: `expectedApprover` is the
    /// approver those words named. A grant signed by anyone else, for another Mac, vault or epoch, or changed, does not
    /// open.
    public func open(
        device: SyncDeviceKeys,
        deviceID: String,
        vaultID: Data,
        expectedApprover: SyncDevicePublicKeys
    ) throws
    -> (key: SyncKey, epoch: UInt32) {
        guard self.vaultID == vaultID.hexString else { throw SyncError.wrongVault }
        guard forDeviceID == deviceID else { throw SyncError.deviceUnknown }
        guard approver == expectedApprover, let signature = Data(base64Encoded: signature),
              let signer = try? expectedApprover.signingKey(),
              try signer.isValidSignature(signature, for: signingBytes()) else { throw SyncError.badSignature }
        let context = Self.context(vaultID: vaultID, epoch: epoch, deviceID: deviceID)
        do {
            var recipient = try HPKE.Recipient(
                privateKey: device.agreement, ciphersuite: Self.suite, info: context, encapsulatedKey: encapsulatedKey
            )
            return try (SyncKey(data: recipient.open(sealedKey, authenticating: context)), epoch)
        } catch {
            throw SyncError.wrongKey
        }
    }
}

extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
