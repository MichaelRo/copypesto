// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// A small backup the app writes for a UI test of the lost-key flow (`RuntimeConfiguration.keyLossFixture`): one clip,
/// a
/// known passphrase, a work folder file. Nothing in a normal launch calls it.
public enum KeyLossFixture {
    public static let passphrase = "fixture passphrase"
    public static let fileName = "key-loss.pestobackup"
    public static let clipText = "Restored from the fixture backup"

    public static func write(to url: URL, now: Date = .now) throws {
        let payload = Data(clipText.utf8)
        let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let metadata = BackupItemMetadata(
            id: UUID(), timestamp: now, typeRaw: "text", mimeType: "public.utf8-plain-text", plainHash: hash
        )
        let data = try BackupFile.write(
            records: [BackupRecord.item(metadata, payload: payload)],
            origin: BackupOrigin(sequence: 1, deviceID: "ui-test", createdAt: now),
            key: BackupKey.generate(), passphrase: passphrase, iterations: 1000
        )
        try data.write(to: url, options: .atomic)
    }
}
