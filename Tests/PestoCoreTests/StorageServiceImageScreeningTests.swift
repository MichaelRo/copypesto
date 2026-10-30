// SPDX-License-Identifier: MIT
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

private final class FakeScreener: ImageSensitivityScreening {
    private let verdict = Mutex(false)

    func say(_ value: Bool) {
        verdict.withLock { $0 = value }
    }

    func isSensitive(imageData _: Data) async -> Bool {
        verdict.withLock { $0 }
    }
}

private final class ModeHolder: @unchecked Sendable {
    private let mode = Mutex(NSFWMode.blur)

    func get() -> NSFWMode {
        mode.withLock { $0 }
    }

    func set(_ value: NSFWMode) {
        mode.withLock { $0 = value }
    }
}

@Suite("StorageService image screening", .serialized)
struct StorageServiceImageScreeningTests {
    private let container: ModelContainer
    private let service: StorageService
    private let screener = FakeScreener()
    private let mode = ModeHolder()

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        let screener = screener
        let mode = mode
        service = StorageService(modelContainer: container, environment: .testing {
            $0.imageScreener = screener
            $0.nsfwMode = { mode.get() }
        })
    }

    private func png() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: Double.random(in: 0...1), green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        try CGImageDestinationAddImage(destination, #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func capture(_ data: Data) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.png", payload: data, payloadString: nil,
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func withMode(_ mode: NSFWMode, _ body: () async throws -> Void) async rethrows {
        self.mode.set(mode)
        try await body()
    }

    private func items() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    @Test("an image the screener calls sensitive is flagged at ingest")
    func whenScreenerSaysSensitive_thenFlagged() async throws {
        screener.say(true)
        try await withMode(.blur) { try await service.ingest(capture(png()))
            await service.waitForBackgroundWork()
        }
        #expect(try items().first?.isNSFW == true)
    }

    @Test("an image the screener passes is not flagged")
    func whenScreenerSaysFine_thenNotFlagged() async throws {
        screener.say(false)
        try await withMode(.blur) { try await service.ingest(capture(png()))
            await service.waitForBackgroundWork()
        }
        #expect(try items().first?.isNSFW == false)
    }

    @Test("with the filter off, images are not screened at all")
    func whenFilterOff_thenNotScreened() async throws {
        screener.say(true)
        try await withMode(.show) { try await service.ingest(capture(png()))
            await service.waitForBackgroundWork()
        }
        #expect(try items().first?.isNSFW == false)
    }

    @Test("turning the filter on can flag images captured earlier")
    func whenRescanned_thenEarlierImagesFlagged() async throws {
        screener.say(false)
        try await withMode(.show) { try await service.ingest(capture(png()))
            await service.waitForBackgroundWork()
        }
        screener.say(true)

        #expect(try await service.rescanNSFWImages() == 1)
        #expect(try items().first?.isNSFW == true)
    }

    @Test("rescanning returns the total count of sensitive clips, including already-flagged ones and links")
    func whenRescannedAgain_thenTotalSensitiveCountReturned() async throws {
        screener.say(true)
        try await withMode(.blur) {
            try await service.ingest(capture(png()))
            let urlText = "https://www.pornhub.com/view_video.php?viewkey=123"
            let urlData = Data(urlText.utf8)
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: urlData, payloadString: urlText,
                contentHash: SHA256.hash(data: urlData).map { String(format: "%02x", $0) }.joined()
            ))
            await service.waitForBackgroundWork()
        }

        #expect(try await service.rescanNSFWImages() == 2)
    }
}
