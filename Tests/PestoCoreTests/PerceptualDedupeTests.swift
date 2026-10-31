// SPDX-License-Identifier: MIT
import AppKit
import CryptoKit
import SwiftData
import Synchronization
import Testing
@testable import PestoCore

private struct NoTextRecognizer: TextRecognizing {
    func recognize(imageData _: Data) async -> String? {
        nil
    }
}

@Suite("Perceptual duplicate images")
struct PerceptualDedupeTests {
    private func gradientRep(editedBlock: Bool = false) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        for x in 0..<64 {
            for y in 0..<64 {
                let shade = CGFloat((x * 4 + (y > 32 ? 60 : 0)) % 256) / 255
                let color = editedBlock && (20..<24).contains(x) && (20..<24).contains(y)
                    ? NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1)
                    : NSColor(calibratedRed: shade, green: 1 - shade, blue: CGFloat(y) / 64, alpha: 1)
                rep.setColor(
                    color,
                    atX: x,
                    y: y
                )
            }
        }
        return rep
    }

    private func capture(_ data: Data, type: String) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: type,
            payload: data,
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    @Test("the same picture in another encoding pops the existing item instead of vanishing")
    func ingest_perceptualDuplicate_popsExistingItem() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(
            modelContainer: container, environment: .testing { $0.textRecognizer = NoTextRecognizer() }
        )
        let rep = try #require(gradientRep())
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let tiff = try #require(rep.tiffRepresentation)
        let clock = Mutex(Date(timeIntervalSince1970: 1000))
        await service.updateClock { clock.withLock { $0 } }

        try await service.ingest(capture(png, type: "public.png"))
        let firstTimestamp = clock.withLock { $0 }
        clock.withLock { $0 = Date(timeIntervalSince1970: 5000) }
        try await service.ingest(capture(tiff, type: "public.tiff"))

        let items = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 1)
        #expect(items[0].timestamp > firstTimestamp)
    }

    @Test("a different picture with a similar coarse hash is stored, not swallowed")
    func ingest_similarButDifferentImage_isStored() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(
            modelContainer: container, environment: .testing { $0.textRecognizer = NoTextRecognizer() }
        )
        let original = try #require(gradientRep()?.representation(using: .png, properties: [:]))
        let edited = try #require(gradientRep(editedBlock: true)?.representation(using: .png, properties: [:]))
        let clock = Mutex(Date(timeIntervalSince1970: 1000))
        await service.updateClock { clock.withLock { $0 } }

        try await service.ingest(capture(original, type: "public.png"))
        clock.withLock { $0 = Date(timeIntervalSince1970: 5000) }
        try await service.ingest(capture(edited, type: "public.png"))

        let items = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 2)
    }

    @Test(
        "restoring a picture that looks like one already here counts as already had, and leaves that clip where it is"
    )
    func restore_lookAlikePicture_isNotCountedAndDoesNotMoveTheExisting() async throws {
        let source = try ModelContainerSetup.makeInMemory()
        let target = try ModelContainerSetup.makeInMemory()
        let sourceService = StorageService(
            modelContainer: source, environment: .testing { $0.textRecognizer = NoTextRecognizer() }
        )
        let targetService = StorageService(
            modelContainer: target, environment: .testing { $0.textRecognizer = NoTextRecognizer() }
        )
        let rep = try #require(gradientRep())
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let tiff = try #require(rep.tiffRepresentation)
        let clock = Mutex(Date(timeIntervalSince1970: 1000))
        await targetService.updateClock { clock.withLock { $0 } }
        try await targetService.ingest(capture(png, type: "public.png"))
        try await sourceService.ingest(capture(tiff, type: "public.tiff"))
        await sourceService.waitForBackgroundWork()
        let export = try await sourceService.backupRecords(includeSensitive: false)
        let key = BackupKey.generate()
        let file = try BackupFile.write(
            records: export.records, origin: BackupOrigin(sequence: 1, deviceID: "test", createdAt: .now),
            key: key, passphrase: "correct horse battery staple", iterations: 1000
        )
        clock.withLock { $0 = Date(timeIntervalSince1970: 9000) }
        let before = try #require(ModelContext(target).fetch(FetchDescriptor<ClipboardItem>()).first).timestamp

        let summary = try await targetService.restore(BackupFile.read(file, credential: .recoveryKey(key)))

        #expect(summary.restored == 0)
        #expect(summary.alreadyHad == 1)
        let items = try ModelContext(target).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 1)
        #expect(items[0].timestamp == before, "a restore must not reorder the history")
    }
}
