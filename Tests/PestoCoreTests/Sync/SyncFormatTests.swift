// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@Suite("Sync format: stamps, segments, vault, head, high-water marks, pairing")
struct SyncFormatTests {
    let key = SyncKey.generate()
    let vaultID = Data((0..<16).map { UInt8($0) })
    let device = SyncDeviceKeys.generate()
    let other = SyncDeviceKeys.generate()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var trust: SyncTrust {
        SyncTrust([device.publicKeys, other.publicKeys])
    }

    private func stamp(_ wall: UInt64, _ counter: UInt32 = 0, _ id: String = "mac-a") -> SyncStamp {
        SyncStamp(wallMillis: wall, counter: counter, deviceID: id)
    }

    private func record(_ sequence: UInt64, device id: String = "mac-a", payload: String = "hello") -> SyncRecord {
        SyncRecord(
            kind: .item, sequence: sequence, stamp: stamp(1000 + sequence, 0, id),
            metadata: Data("{\"n\":\(sequence)}".utf8), payload: Data(payload.utf8)
        )
    }

    private func temp(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pesto-sync-\(name)")
    }

    /// A finished segment with `count` records, returned as its bytes and manifest.
    private func segment(
        count: Int = 3, firstSequence: UInt64 = 1, deviceID: String = "mac-a", keys: SyncDeviceKeys? = nil,
        epoch: UInt32 = 1, previous: String = SyncManifest.zeroHash, syncKey: SyncKey? = nil, snapshot: Bool = false
    ) throws
    -> (data: Data, manifest: SyncManifest) {
        let partial = temp(), final = temp()
        defer { try? FileManager.default.removeItem(at: final) }
        let writer = try SyncSegmentWriter(partialURL: partial, context: .init(
            syncKey: syncKey ?? key, vaultID: vaultID, epoch: epoch, deviceID: deviceID, device: keys ?? device,
            previousManifestHash: previous, isSnapshot: snapshot
        ))
        for offset in 0..<count {
            try writer.append(record(firstSequence + UInt64(offset), device: deviceID))
        }
        let manifest = try writer.finish(to: final, now: now)
        return try (Data(contentsOf: final), manifest)
    }

    private func verify(_ data: Data, epoch: UInt32 = 1, trust: SyncTrust? = nil, syncKey: SyncKey? = nil) throws
    -> VerifiedSyncSegment {
        try SyncSegmentReader.verify(
            data, syncKey: syncKey ?? key, trust: trust ?? self.trust, vaultID: vaultID, epoch: epoch
        )
    }

    // MARK: Stamps

    @Test("a stamp orders by wall time, then counter, then device")
    func stampOrder() {
        #expect(stamp(1) < stamp(2))
        #expect(stamp(2, 0) < stamp(2, 1))
        #expect(stamp(2, 1, "a") < stamp(2, 1, "b"))
    }

    @Test("a local change is later than the last, even when the clock did not move or moved back")
    func nextStamp() {
        let last = stamp(5000, 3)
        let sameMillis = SyncStamp.next(after: last, now: Date(timeIntervalSince1970: 5), deviceID: "mac-a")
        let earlier = SyncStamp.next(after: last, now: Date(timeIntervalSince1970: 1), deviceID: "mac-a")
        let later = SyncStamp.next(after: last, now: Date(timeIntervalSince1970: 9), deviceID: "mac-a")
        #expect(sameMillis > last && earlier > last && later > last)
        #expect(later.counter == 0)
    }

    @Test("receiving a stamp makes the clock later than both, and a stamp from the far future is refused")
    func receiveStamp() throws {
        let local = stamp(5000, 2)
        let remote = stamp(5000, 7, "mac-b")
        let merged = try local.receiving(remote, now: Date(timeIntervalSince1970: 1), deviceID: "mac-a")
        #expect(merged > local && merged > remote)
        let farAhead = SyncStamp(
            wallMillis: SyncStamp.millis(now) + 8 * 24 * 3600 * 1000,
            counter: 0,
            deviceID: "mac-b"
        )
        #expect(throws: SyncError.clockFarAhead) { try local.receiving(farAhead, now: now, deviceID: "mac-a") }
    }

    // MARK: Keys

    @Test("a recovery key round-trips, tolerates case and spaces, and rejects a typo")
    func recoveryKey() throws {
        let text = key.recoveryKey
        #expect(try SyncKey(recoveryKey: text) == key)
        #expect(try SyncKey(recoveryKey: text.lowercased().replacingOccurrences(of: "-", with: " ")) == key)
        var typo = Array(text)
        let index = typo.firstIndex { $0 != "-" } ?? 0
        typo[index] = typo[index] == "A" ? "B" : "A"
        #expect(throws: SyncError.self) { try SyncKey(recoveryKey: String(typo)) }
    }

    @Test("device keys survive their 64-byte form, and a key id names the signing key")
    func deviceKeys() throws {
        let restored = try SyncDeviceKeys(rawRepresentation: device.rawRepresentation)
        #expect(restored.publicKeys == device.publicKeys)
        #expect(device.publicKeys.keyID != other.publicKeys.keyID)
    }

    // MARK: Segments

    @Test("a segment round-trips its records in order")
    func segmentRoundTrip() throws {
        let made = try segment(count: 5)
        let verified = try verify(made.data)
        #expect(verified.manifest == made.manifest)
        #expect(try verified.records() == (1...5).map { record(UInt64($0)) })
    }

    @Test("every single changed byte of a segment is caught")
    func everyByteFlipIsCaught() throws {
        let made = try segment(count: 2)
        for index in made.data.indices {
            var damaged = made.data
            damaged[index] ^= 0x01
            #expect((try? verify(damaged).records()) == nil, "byte \(index) changed without notice")
        }
    }

    @Test("a truncated segment, or one with extra bytes, is refused")
    func truncationAndTrailing() throws {
        let made = try segment()
        for cut in stride(from: 1, to: made.data.count, by: 7) {
            #expect((try? verify(made.data.prefix(made.data.count - cut))) == nil, "cut \(cut)")
        }
        #expect((try? verify(made.data + Data([0, 0, 0, 1]))) == nil)
    }

    @Test("the wrong key, vault, epoch or signer is refused")
    func wrongContext() throws {
        let made = try segment()
        #expect(throws: SyncError.wrongKey) { try verify(made.data, syncKey: .generate()) }
        #expect(throws: SyncError.wrongEpoch) { try verify(made.data, epoch: 2) }
        #expect(throws: SyncError.wrongVault) {
            try SyncSegmentReader.verify(
                made.data,
                syncKey: key,
                trust: trust,
                vaultID: Data(repeating: 9, count: 16),
                epoch: 1
            )
        }
        #expect(throws: SyncError.unknownSigner) { try verify(made.data, trust: SyncTrust([other.publicKeys])) }
    }

    @Test("a chunk spliced in from another segment does not open")
    func splicedChunk() throws {
        let first = try segment(count: 3)
        let second = try segment(count: 3)
        let header = SyncSegmentFormat.headerLength
        var spliced = first.data
        let length = Int(first.data.subdata(in: header..<header + 4).reduce(0) { $0 << 8 | UInt32($1) }) + 4
        let range = header..<header + length
        guard second.data.count >= range.upperBound else { return }
        spliced.replaceSubrange(range, with: second.data.subdata(in: range))
        #expect((try? verify(spliced).records()) == nil)
    }

    @Test("a segment signed by a device that is trusted but claims another device's records is refused")
    func forgedDevice() throws {
        let made = try segment(count: 2, deviceID: "mac-b", keys: other)
        let verified = try verify(made.data)
        #expect(verified.manifest.deviceID == "mac-b")
        #expect(throws: SyncError.self) {
            // Records stamped as mac-a inside a manifest for mac-b are out of place.
            let partial = temp(), final = temp()
            defer { try? FileManager.default.removeItem(at: final) }
            let writer = try SyncSegmentWriter(partialURL: partial, context: .init(
                syncKey: key, vaultID: vaultID, epoch: 1, deviceID: "mac-b", device: other
            ))
            try writer.append(record(1, device: "mac-a"))
            try writer.finish(to: final)
            _ = try verify(Data(contentsOf: final)).records()
        }
    }

    @Test("a sequence gap while writing is refused")
    func sequenceGap() throws {
        let writer = try SyncSegmentWriter(partialURL: temp(), context: .init(
            syncKey: key, vaultID: vaultID, epoch: 1, deviceID: "mac-a", device: device
        ))
        try writer.append(record(1))
        #expect(throws: SyncError.self) { try writer.append(record(3)) }
        writer.abandon()
    }

    // MARK: Vault, head

    @Test("a vault round-trips, checks the key, and a changed byte breaks its signature")
    func vault() throws {
        let vault = SyncVault.create(vaultID: vaultID, epoch: 2, syncKey: key, creator: device)
        let data = try vault.serialized(signedBy: device)
        let parsed = try SyncVault.parse(data)
        #expect(parsed == vault)
        #expect(parsed.accepts(key) && !parsed.accepts(.generate()))
        for index in data.indices {
            var damaged = data
            damaged[index] ^= 0x01
            #expect((try? SyncVault.parse(damaged)) == nil, "vault byte \(index)")
        }
    }

    @Test("a head round-trips, hides its cursors from other keys and refuses a bad signer")
    func head() throws {
        let head = SyncHead(
            deviceID: "mac-a", epoch: 1, lastSequence: 9, lastManifestHash: "abc", cursors: ["mac-b": 4],
            writtenAt: now, signerKeyID: device.publicKeys.keyID
        )
        let data = try head.sealed(syncKey: key, signedBy: device)
        var expected = head
        expected.signature = try SyncHead.open(data, syncKey: key, trust: trust, deviceID: "mac-a", epoch: 1).signature
        #expect(try SyncHead.open(data, syncKey: key, trust: trust, deviceID: "mac-a", epoch: 1) == expected)
        #expect(throws: SyncError.wrongKey) {
            try SyncHead.open(data, syncKey: .generate(), trust: trust, deviceID: "mac-a", epoch: 1)
        }
        #expect(throws: SyncError.wrongKey) { try SyncHead.open(
            data,
            syncKey: key,
            trust: trust,
            deviceID: "mac-b",
            epoch: 1
        ) }
        #expect(throws: SyncError.unknownSigner) {
            try SyncHead.open(data, syncKey: key, trust: SyncTrust(), deviceID: "mac-a", epoch: 1)
        }
    }

    // MARK: High-water marks

    @Test("the next segment applies, a replay is a duplicate, a gap waits, and rollback, fork and a broken chain throw")
    func highWater() throws {
        let first = try segment(count: 2)
        let second = try segment(count: 2, firstSequence: 3, previous: first.manifest.hash())
        let forked = try segment(count: 2, firstSequence: 3, previous: first.manifest.hash())
        let gap = try segment(count: 1, firstSequence: 9, previous: second.manifest.hash())
        let broken = try segment(count: 1, firstSequence: 3, previous: SyncManifest.zeroHash)

        var water = SyncHighWater()
        #expect(try water.decide(first.manifest, currentEpoch: 1) == .apply)
        try water.record(first.manifest)
        #expect(try water.decide(first.manifest, currentEpoch: 1) == .duplicate)
        #expect(try water.decide(second.manifest, currentEpoch: 1) == .apply)
        try water.record(second.manifest)
        #expect(try water.decide(first.manifest, currentEpoch: 1) == .duplicate)
        #expect(try water.decide(gap.manifest, currentEpoch: 1) == .gap)
        #expect(throws: SyncError.fork) { try water.decide(forked.manifest, currentEpoch: 1) }
        var other = SyncHighWater()
        try other.record(first.manifest)
        #expect(throws: SyncError.brokenChain) { try other.decide(broken.manifest, currentEpoch: 1) }
        #expect(throws: SyncError.wrongEpoch) { try water.decide(second.manifest, currentEpoch: 2) }
    }

    @Test(
        "a snapshot after a gap applies, an ordinary segment after a gap waits, old manifests are unchanged"
    )
    func snapshotAfterGap() throws {
        let first = try segment(count: 2)
        let snapshot = try segment(count: 3, firstSequence: 9, previous: SyncManifest.zeroHash, snapshot: true)
        let later = try segment(count: 1, firstSequence: 12, previous: snapshot.manifest.hash())
        let plain = try segment(count: 1, firstSequence: 9, previous: SyncManifest.zeroHash)

        var water = SyncHighWater()
        try water.record(first.manifest)
        #expect(try water.decide(plain.manifest, currentEpoch: 1) == .gap)
        #expect(try water.decide(snapshot.manifest, currentEpoch: 1) == .apply)
        try water.record(snapshot.manifest)
        #expect(try water.decide(later.manifest, currentEpoch: 1) == .apply)
        #expect(first.manifest.snapshot == nil)
        #expect(try verify(snapshot.data).manifest.snapshot == true)
        let fresh = SyncHighWater()
        #expect(try fresh.decide(snapshot.manifest, currentEpoch: 1) == .apply)
    }

    // MARK: Pairing words

    @Test("the pairing words are the same on both Macs, change with the vault or a key, and come from a clean list")
    func pairingWords() {
        let a = device.publicKeys.agreement, b = other.publicKeys.agreement
        let words = SyncPairingCode.words(vaultID: vaultID, keyA: a, keyB: b)
        #expect(words.count == 6)
        #expect(words == SyncPairingCode.words(vaultID: vaultID, keyA: b, keyB: a))
        #expect(words != SyncPairingCode.words(vaultID: Data(repeating: 1, count: 16), keyA: a, keyB: b))
        #expect(words != SyncPairingCode.words(
            vaultID: vaultID,
            keyA: a,
            keyB: SyncDeviceKeys.generate().publicKeys.agreement
        ))
        #expect(SyncWordList.words.count == 1024)
        #expect(Set(SyncWordList.words).count == 1024)
        #expect(SyncWordList.words.allSatisfy { $0.range(of: "^[a-z]{3,7}$", options: .regularExpression) != nil })
    }
}
