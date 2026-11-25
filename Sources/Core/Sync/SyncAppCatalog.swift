// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// `devices/<id>/apps.pestoapps`: the apps a Mac's clips came from, with each one's name, icon and color, so a device
/// that cannot look an app up (an iPhone) can show them (ADR 0068). Sealed under the sync key and signed by the Mac,
/// like its head; written only by that Mac, read through `SyncSmallFile`. It holds no clip and no clip's text, only
/// what the shelf already shows beside a clip. An older device ignores the file.
public struct SyncAppCatalog: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var bundleID: String
        public var name: String
        public var colorHex: String
        public var icon: Data

        public init(bundleID: String, name: String, colorHex: String, icon: Data) {
            self.bundleID = bundleID
            self.name = name
            self.colorHex = colorHex
            self.icon = icon
        }

        /// A bundle id and name of sane length, a `#RRGGBB` color and a PNG icon within bounds; anything else is
        /// dropped rather than shown.
        var isWellFormed: Bool {
            let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            return (1...255).contains(bundleID.utf8.count) && (1...128).contains(name.utf8.count)
                && SyncAppCatalog.isColorHex(colorHex)
                && icon.count <= SyncAppCatalog.maxIconBytes && icon.starts(with: pngSignature)
        }
    }

    public static let maxEntries = 128
    public static let maxIconBytes = 8 * 1024

    public var deviceID: String
    public var epoch: UInt32
    public var entries: [Entry]
    public var signerKeyID: String
    public var signature: String = ""

    public init(deviceID: String, epoch: UInt32, entries: [Entry], signerKeyID: String) {
        self.deviceID = deviceID
        self.epoch = epoch
        self.entries = Self.bounded(entries)
        self.signerKeyID = signerKeyID
    }

    static func bounded(_ entries: [Entry]) -> [Entry] {
        var seen = Set<String>()
        return Array(entries.filter { $0.isWellFormed && seen.insert($0.bundleID).inserted }.prefix(maxEntries))
    }

    static func isColorHex(_ value: String) -> Bool {
        value.count == 7 && value.first == "#" && value.dropFirst().allSatisfy(\.isHexDigit)
    }

    private static let magic = Data("PSTOAPPS".utf8)

    private func signingBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = ""
        return try SyncManifest.canonical(unsigned)
    }

    private static func key(_ syncKey: SyncKey, deviceID: String) -> SymmetricKey {
        syncKey.subkey(salt: Data(deviceID.utf8), info: "pesto.sync.apps.v1")
    }

    private static func associatedData(deviceID: String, epoch: UInt32) -> Data {
        var out = magic + Data(deviceID.utf8)
        out.appendBigEndian(epoch)
        return out
    }

    /// The sealed catalog, with the oldest apps dropped until it fits under `SyncSmallFile.maxBytes`: 128 icons of
    /// 8 KB come to about 1.4 MB as JSON, and a reader refuses a file over the limit without a word.
    public func sealed(syncKey: SyncKey, signedBy keys: SyncDeviceKeys) throws -> Data {
        var fitting = self
        while true {
            let data = try fitting.sealedAsIs(syncKey: syncKey, signedBy: keys)
            guard data.count > SyncSmallFile.maxBytes, fitting.entries.count > 1 else { return data }
            let over = Double(data.count) / Double(SyncSmallFile.maxBytes)
            let keep = max(1, min(fitting.entries.count - 1, Int(Double(fitting.entries.count) / over * 0.95)))
            fitting.entries = Array(fitting.entries.prefix(keep))
        }
    }

    private func sealedAsIs(syncKey: SyncKey, signedBy keys: SyncDeviceKeys) throws -> Data {
        var copy = self
        copy.signature = try keys.signing.signature(for: signingBytes()).base64EncodedString()
        let box = try AES.GCM.seal(
            SyncManifest.canonical(copy), using: Self.key(syncKey, deviceID: deviceID),
            authenticating: Self.associatedData(deviceID: deviceID, epoch: epoch)
        )
        guard let combined = box.combined else { throw SyncError.malformed("app catalog") }
        return Self.magic + combined
    }

    /// Opens the catalog `deviceID` wrote for `epoch`, keeping only well-formed entries within the bounds.
    public static func open(
        _ data: Data, syncKey: SyncKey, trust: SyncTrust, deviceID: String, epoch: UInt32
    ) throws
    -> SyncAppCatalog {
        guard data.count > magic.count, data.prefix(magic.count) == magic else {
            throw SyncError.malformed("not an app catalog")
        }
        let plain: Data
        do {
            plain = try AES.GCM.open(
                AES.GCM.SealedBox(combined: Data(data.dropFirst(magic.count))),
                using: key(syncKey, deviceID: deviceID),
                authenticating: associatedData(deviceID: deviceID, epoch: epoch)
            )
        } catch {
            throw SyncError.wrongKey
        }
        var catalog = try JSONDecoder().decode(SyncAppCatalog.self, from: plain)
        guard catalog.deviceID == deviceID, catalog.epoch == epoch,
              let signature = Data(base64Encoded: catalog.signature) else
        {
            throw SyncError.malformed("app catalog fields")
        }
        try trust.verify(signature, over: catalog.signingBytes(), signerID: catalog.signerKeyID, deviceID: deviceID)
        catalog.entries = bounded(catalog.entries)
        return catalog
    }
}
