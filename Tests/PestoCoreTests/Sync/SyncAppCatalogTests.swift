// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The apps a Mac's clips came from, as other devices read them")
struct SyncAppCatalogTests {
    let key = SyncKey.generate()
    let device = SyncDeviceKeys.generate()
    let other = SyncDeviceKeys.generate()

    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])

    var trust: SyncTrust {
        SyncTrust([device.publicKeys, other.publicKeys], devices: ["mac-a": device.publicKeys.keyID])
    }

    private func catalog(_ entries: [SyncAppCatalog.Entry]) -> SyncAppCatalog {
        SyncAppCatalog(deviceID: "mac-a", epoch: 1, entries: entries, signerKeyID: device.publicKeys.keyID)
    }

    private let notes = SyncAppCatalog.Entry(
        bundleID: "com.apple.Notes", name: "Notes", colorHex: "#FAD927", icon: png
    )

    @Test("a catalog round-trips and opens only with its key, its device, its epoch and its signer")
    func whenSealed_thenOnlyTheRightReaderOpensIt() throws {
        let data = try catalog([notes]).sealed(syncKey: key, signedBy: device)
        let opened = try SyncAppCatalog.open(data, syncKey: key, trust: trust, deviceID: "mac-a", epoch: 1)
        #expect(opened.entries == [notes])
        #expect(throws: SyncError.wrongKey) {
            try SyncAppCatalog.open(data, syncKey: .generate(), trust: trust, deviceID: "mac-a", epoch: 1)
        }
        #expect(throws: SyncError.wrongKey) {
            try SyncAppCatalog.open(data, syncKey: key, trust: trust, deviceID: "mac-b", epoch: 1)
        }
        #expect(throws: SyncError.wrongKey) {
            try SyncAppCatalog.open(data, syncKey: key, trust: trust, deviceID: "mac-a", epoch: 2)
        }
        let forged = try catalog([notes]).sealed(syncKey: key, signedBy: other)
        #expect(throws: (any Error).self) {
            try SyncAppCatalog.open(forged, syncKey: key, trust: trust, deviceID: "mac-a", epoch: 1)
        }
    }

    @Test("any changed byte is refused")
    func whenDamaged_thenRefused() throws {
        let data = try catalog([notes]).sealed(syncKey: key, signedBy: device)
        for index in data.indices {
            var damaged = data
            damaged[index] ^= 0x01
            #expect(
                (try? SyncAppCatalog.open(damaged, syncKey: key, trust: trust, deviceID: "mac-a", epoch: 1)) == nil,
                "byte \(index)"
            )
        }
    }

    @Test("a full catalog of the largest icons still fits the small-file limit its readers enforce")
    func whenEveryIconIsAtItsLimit_thenTheSealedFileStillOpens() throws {
        let icon = Self
            .png +
            Data((0..<(SyncAppCatalog.maxIconBytes - Self.png.count)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let full = (0..<SyncAppCatalog.maxEntries).map {
            SyncAppCatalog.Entry(bundleID: "app.\($0)", name: "App \($0)", colorHex: "#112233", icon: icon)
        }
        let data = try catalog(full).sealed(syncKey: key, signedBy: device)
        #expect(data.count <= SyncSmallFile.maxBytes)
        let opened = try SyncAppCatalog.open(data, syncKey: key, trust: trust, deviceID: "mac-a", epoch: 1)
        #expect(opened.entries.count > 64, "the newest apps are kept")
        #expect(opened.entries.first == full.first)
    }

    @Test("entries that are not a PNG, too large, badly colored, repeated or past the limit are dropped")
    func whenEntriesAreOutOfBounds_thenDropped() {
        let big = SyncAppCatalog.Entry(
            bundleID: "big", name: "Big", colorHex: "#112233",
            icon: Self.png + Data(count: SyncAppCatalog.maxIconBytes)
        )
        let notPNG = SyncAppCatalog.Entry(bundleID: "jpg", name: "JPG", colorHex: "#112233", icon: Data([0xFF, 0xD8]))
        let badColor = SyncAppCatalog.Entry(bundleID: "c", name: "C", colorHex: "red", icon: Self.png)
        let many = (0..<200).map {
            SyncAppCatalog.Entry(bundleID: "app.\($0)", name: "App", colorHex: "#112233", icon: Self.png)
        }
        let kept = catalog([notes, big, notPNG, badColor, notes] + many).entries
        #expect(kept.first == notes)
        #expect(kept.count == SyncAppCatalog.maxEntries)
        #expect(!kept.contains { ["big", "jpg", "c"].contains($0.bundleID) })
        #expect(kept.count(where: { $0.bundleID == notes.bundleID }) == 1)
    }

    @Test("an item record carries the app's color, and one written before it existed still reads")
    func whenItemRecordHasColor_thenItRoundTrips() throws {
        var meta = SyncItemRecord(id: UUID(), plainHash: "abc", mimeType: "public.utf8-plain-text", timestamp: .now)
        meta.sourceColorHex = "#FAD927"
        let encoded = try SyncRecord.encode(meta)
        let record = SyncRecord(
            kind: .item,
            sequence: 1,
            stamp: SyncStamp(wallMillis: 1, counter: 0, deviceID: "a"),
            metadata: encoded
        )
        #expect(try record.decodeMetadata(SyncItemRecord.self).sourceColorHex == "#FAD927")
        let old = #"{"curation":{"isPinned":false,"tags":[]},"id":"\#(UUID().uuidString)","isRemote":false,"#
            + #""mimeType":"public.utf8-plain-text","plainHash":"abc","timestamp":1}"#
        let older = SyncRecord(
            kind: .item,
            sequence: 1,
            stamp: SyncStamp(wallMillis: 1, counter: 0, deviceID: "a"),
            metadata: Data(old.utf8)
        )
        #expect(try older.decodeMetadata(SyncItemRecord.self).sourceColorHex == nil)
    }
}
