// SPDX-License-Identifier: MIT
import Foundation

/// `devices/<id>/identity.pestokey`: the public halves of an enrolled Mac's keys, signed by the Mac, readable by anyone
/// with the folder. A Mac that wants to join reads one to learn which approver's six words to show, before it has the
/// sync key. It carries nothing secret; what protects the join is the person comparing the words on both screens.
public struct SyncPublicIdentity: Codable, Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var keys: SyncDevicePublicKeys
    public var signature: String = ""

    public init(deviceID: String, name: String, keys: SyncDevicePublicKeys) {
        self.deviceID = deviceID
        self.name = name
        self.keys = keys
    }

    private func signingBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = ""
        return try SyncManifest.canonical(unsigned)
    }

    public func serialized(signedBy device: SyncDeviceKeys) throws -> Data {
        var copy = self
        copy.signature = try device.signing.signature(for: signingBytes()).base64EncodedString()
        return try SyncManifest.canonical(copy)
    }

    public static func parse(_ data: Data) throws -> SyncPublicIdentity {
        let identity = try JSONDecoder().decode(SyncPublicIdentity.self, from: data)
        guard let signature = Data(base64Encoded: identity.signature), let signer = try? identity.keys.signingKey(),
              try signer.isValidSignature(signature, for: identity.signingBytes()) else { throw SyncError.badSignature }
        return identity
    }
}
