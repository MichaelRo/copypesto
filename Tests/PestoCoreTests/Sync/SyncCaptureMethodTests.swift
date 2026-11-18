// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("How a clip was made stays on the device that made it", .serialized)
@MainActor
struct SyncCaptureMethodTests {
    private func capture(_ text: String, at date: Date, method: CaptureMethod?) -> PasteboardCapture {
        let payload = Data(text.utf8)
        return PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text, timestamp: date,
            contentHash: Data(SHA256.hash(data: payload)).hexString
        ).with(captureMethod: method)
    }

    @Test("ingest seals the method into the clip's metadata and nowhere in the clear")
    func whenCapturedWithAMethod_thenItIsSealedOnTheClip() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container, environment: .testing())
        try await service.ingest(capture("shared from Safari", at: .now, method: .share))

        let item = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(item.captureMethod == .share)
        #expect(item.metadataCiphertext != nil)
        #expect(item.metadataCiphertext?.range(of: Data("share".utf8)) == nil)
    }

    @Test("the method changes no sync fingerprint, so setting it stamps nothing")
    func whenMethodSet_thenTheFingerprintIsTheSame() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container, environment: .testing())
        try await service.ingest(capture("noted", at: .now, method: nil))
        let item = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        let before = item.syncFingerprintValue()
        item.updateMetadata { $0.captureMethod = .note }
        #expect(item.syncFingerprintValue() == before)
    }

    @Test("a sync record carries no method: its fields are those of a clip made without one, and it arrives without")
    func whenPublished_thenTheRecordIsTheSameAsWithoutAMethod() async throws {
        let world = try SyncWorld(["iphone", "mac-b"])
        let (phone, mac) = (world.macs[0], world.macs[1])
        let date = world.time.now
        try await phone.service.ingest(capture("pasted on the phone", at: date, method: .paste))
        try await phone.service.ingest(capture("plain copy", at: date.addingTimeInterval(1), method: nil))

        let records = try await world.publish(from: phone)
        let items = try records.filter { $0.kind == .item }.map { try $0.decodeMetadata(SyncItemRecord.self) }
        #expect(items.count == 2)
        let keys = try records.filter { $0.kind == .item }.map { record in
            try Set(#require(JSONSerialization.jsonObject(with: record.metadata) as? [String: Any]).keys)
        }
        #expect(keys.count == 2)
        #expect(keys.first == keys.last, "the record of a clip with a method has exactly the fields of one without")
        for record in records {
            #expect(record.metadata.range(of: Data("captureMethod".utf8)) == nil)
            #expect(record.payload.range(of: Data("captureMethod".utf8)) == nil)
        }

        try await world.apply(records, on: mac)
        let arrived = try #require(try world.clip("pasted on the phone", on: mac))
        #expect(arrived.captureMethod == nil)
        #expect(try world.clip("pasted on the phone", on: phone)?.captureMethod == .paste)
    }
}
