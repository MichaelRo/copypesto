// SPDX-License-Identifier: MIT
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

@Suite("Sync dedup and delete across Mac and iPhone", .serialized)
@MainActor
struct SyncDedupDeleteTests {
    private func makeImageData(format: UTType) throws -> Data {
        let width = 64
        let height = 64
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for x in 0..<width {
            for y in 0..<height {
                let shade = CGFloat((x * 4 + (y > 32 ? 60 : 0)) % 256) / 255
                context.setFillColor(CGColor(
                    srgbRed: shade, green: 1 - shade, blue: CGFloat(y) / 64, alpha: 1
                ))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, format.identifier as CFString, 1, nil)
        )
        let properties: [CFString: Any] = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: 0.9]
            : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func makeGIFData() -> Data {
        // Minimal 1x1 GIF89a header + trailer, distinct from PNG/JPEG.
        Data([
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
            0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
            0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B
        ])
    }

    private func capture(
        _ data: Data, type: String, isRemote: Bool = false, at timestamp: Date
    )
    -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: type,
            payload: data,
            frontmostBundleID: isRemote ? nil : "com.apple.mobilesafari",
            timestamp: timestamp,
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            isRemote: isRemote
        )
    }

    @Test("exact-hash GIF copied on iPhone, synced from Mac, re-pasted on iOS, and deleted removes Mac's copy")
    func whenExactGIFRepastedOnIOSAndDeleted_thenMacCopyIsDeleted() async throws {
        let world = try SyncWorld(["mac", "iphone"])
        let mac = world.macs[0]
        let iphone = world.macs[1]
        let gif = makeGIFData()

        world.tick()
        try await mac.service.ingest(capture(gif, type: "com.compuserve.gif", isRemote: true, at: world.time.now))
        await mac.service.waitForBackgroundWork()
        let macOut = try await world.publish(from: mac)
        try await world.apply(macOut, on: iphone)
        await iphone.service.waitForBackgroundWork()
        #expect(try world.clips(on: iphone).count == 1)

        // iPhone re-pastes the same GIF (e.g. via Paste button or Adds Copies on Open)
        world.tick()
        try await iphone.service.ingest(capture(gif, type: "com.compuserve.gif", isRemote: false, at: world.time.now))
        let iphoneClips = try world.clips(on: iphone)
        #expect(iphoneClips.count == 1)
        #expect(!iphoneClips[0].isRemote)

        // iPhone deletes the clip -> syncs tombstone back to Mac
        world.tick()
        try await iphone.service.deleteItems(ids: [iphoneClips[0].id], reason: .user)
        let iphoneOut = try await world.publish(from: iphone)
        try await world.apply(iphoneOut, on: mac)

        #expect(try world.clips(on: iphone).isEmpty)
        #expect(try world.clips(on: mac).isEmpty)
    }

    @Test("lookalike picture synced from Mac, re-pasted on iOS in another format, and deleted removes Mac's copy")
    func whenLookalikeRepastedOnIOSAndDeleted_thenMacCopyIsDeleted() async throws {
        let world = try SyncWorld(["mac", "iphone"])
        let mac = world.macs[0]
        let iphone = world.macs[1]
        let macPNG = try makeImageData(format: .png)
        let iosJPEG = try makeImageData(format: .jpeg)

        world.tick()
        try await mac.service.ingest(capture(macPNG, type: "public.png", isRemote: true, at: world.time.now))
        await mac.service.waitForBackgroundWork()
        let macOut = try await world.publish(from: mac)
        try await world.apply(macOut, on: iphone)
        await iphone.service.waitForBackgroundWork()
        #expect(try world.clips(on: iphone).count == 1)

        // iPhone re-pastes re-encoded JPEG of the same picture
        world.tick()
        try await iphone.service.ingest(capture(iosJPEG, type: "public.jpeg", isRemote: false, at: world.time.now))
        let iphoneClips = try world.clips(on: iphone)
        #expect(iphoneClips.count == 1)
        #expect(!iphoneClips[0].isRemote)

        world.tick()
        try await iphone.service.deleteItems(ids: [iphoneClips[0].id], reason: .user)
        let iphoneOut = try await world.publish(from: iphone)
        try await world.apply(iphoneOut, on: mac)

        #expect(try world.clips(on: iphone).isEmpty)
        #expect(try world.clips(on: mac).isEmpty)
    }

    @Test("addsCopiesOnOpen ingesting JPEG on iPhone before Mac's PNG arrives folds IDs and deletes both on delete")
    func whenAddsCopiesOnOpenRunsBeforeSync_thenLookalikeFoldsAndDeletesBothDevices() async throws {
        let world = try SyncWorld(["mac", "iphone"])
        let mac = world.macs[0]
        let iphone = world.macs[1]
        let macPNG = try makeImageData(format: .png)
        let iosJPEG = try makeImageData(format: .jpeg)

        // Mac captures Universal Clipboard PNG; iPhone opens with addsCopiesOnOpen and captures JPEG before sync
        world.tick()
        try await mac.service.ingest(capture(macPNG, type: "public.png", isRemote: true, at: world.time.now))
        await mac.service.waitForBackgroundWork()
        world.tick()
        try await iphone.service.ingest(capture(iosJPEG, type: "public.jpeg", isRemote: false, at: world.time.now))
        await iphone.service.waitForBackgroundWork()

        let macOut = try await world.publish(from: mac)
        let iphoneOut1 = try await world.publish(from: iphone)
        try await world.apply(macOut, on: iphone)
        try await world.apply(iphoneOut1, on: mac)

        #expect(try world.clips(on: iphone).count == 1)
        #expect(try world.clips(on: mac).count == 1)

        // User deletes on iPhone -> Mac's distinct-ID, distinct-hash PNG must also be deleted via foldedSyncIDs
        world.tick()
        let doomedID = try #require(world.clips(on: iphone).first?.id)
        try await iphone.service.deleteItems(ids: [doomedID], reason: .user)
        let iphoneOut2 = try await world.publish(from: iphone)
        try await world.apply(iphoneOut2, on: mac)

        #expect(try world.clips(on: iphone).isEmpty)
        #expect(try world.clips(on: mac).isEmpty)
    }

    @Test("NSFW flag syncs immediately to peer device and older SyncCuration JSON decodes cleanly")
    func whenNSFWSynced_thenPeerReceivesFlagImmediatelyAndOldJSONDecodes() async throws {
        let oldJSON = Data(#"{"customTitle":"T","tags":[],"isPinned":false}"#.utf8)
        let decodedOld = try JSONDecoder().decode(SyncCuration.self, from: oldJSON)
        #expect(decodedOld.isNSFW == nil)

        let world = try SyncWorld(["mac", "iphone"])
        let mac = world.macs[0]
        let iphone = world.macs[1]
        let png = try makeImageData(format: .png)

        world.tick()
        try await mac.service.ingest(capture(png, type: "public.png", isRemote: false, at: world.time.now))
        await mac.service.waitForBackgroundWork()
        let macClip = try #require(world.clips(on: mac).first)

        // Mark as Sensitive on Mac
        world.tick()
        let context = ModelContext(mac.container)
        let id = macClip.id
        let item = try #require(context.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id }))
            .first)
        item.isNSFW = true
        try context.saveOrRollback()

        let macOut = try await world.publish(from: mac)
        try await world.apply(macOut, on: iphone)

        let synced = try #require(world.clips(on: iphone).first)
        #expect(synced.isNSFW)

        // Mark as Not Sensitive on Mac -> propagates false back to iPhone
        world.tick()
        item.isNSFW = false
        try context.saveOrRollback()
        let macOut2 = try await world.publish(from: mac)
        try await world.apply(macOut2, on: iphone)
        let refreshed = try #require(world.clips(on: iphone).first)
        #expect(!refreshed.isNSFW)
    }
}
