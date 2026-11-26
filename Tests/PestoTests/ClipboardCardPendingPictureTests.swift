// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("A Mac picture card waits for its verdict", .serialized)
    @MainActor
    struct ClipboardCardPendingPictureTests {
        /// Sets the content filter for one test and puts back what was there, whatever the test does.
        private func withMode(_ mode: NSFWMode, _ body: () throws -> Void) rethrows {
            let key = Setting.nsfwMode.name
            let saved = AppDefaults.store.string(forKey: key)
            AppDefaults.store.set(mode.rawValue, forKey: key)
            ThumbnailCache.shared.clear()
            defer {
                if let saved {
                    AppDefaults.store.set(saved, forKey: key)
                } else {
                    AppDefaults.store.removeObject(forKey: key)
                }
                ThumbnailCache.shared.clear()
            }
            try body()
        }

        @Test("while the content filter is on, a pending picture shows its placeholder, not its pixels")
        func whenPictureIsPendingAndFilteringIsOn_thenItsPixelsAreNotDrawn() throws {
            try withMode(.blur) {
                let center = try renderedCenter(analysisPending: true)
                #expect(!Self.isRed(center))
            }
        }

        @Test("with the content filter off, a pending picture shows at once")
        func whenPictureIsPendingAndFilteringIsOff_thenItShows() throws {
            try withMode(.show) {
                let center = try renderedCenter(analysisPending: true)
                #expect(Self.isRed(center))
            }
        }

        @Test("a judged picture shows with the content filter on")
        func whenPictureIsJudged_thenItShows() throws {
            try withMode(.blur) {
                let center = try renderedCenter(analysisPending: false)
                #expect(Self.isRed(center))
            }
        }

        private static func isRed(_ color: NSColor) -> Bool {
            color.redComponent > 0.7 && color.greenComponent < 0.3 && color.blueComponent < 0.3
        }

        private func renderedCenter(analysisPending: Bool) throws -> NSColor {
            let container = try ModelContainerSetup.makeInMemory()
            let context = ModelContext(container)
            let (image, pngData) = try Self.solidRed()
            let item = ClipboardItem(
                type: .image, sourceAppName: "Preview", previewText: "", contentHash: UUID().uuidString,
                byteSize: pngData.count, deviceID: "test-device", sequenceNumber: 1
            )
            item.analysisPending = analysisPending
            item.blob = ClipboardBlob(encryptedData: Data(), nonceData: Data(), mimeType: "public.png")
            context.insert(item)
            try context.saveOrRollback()
            ThumbnailCache.shared.store(.init(image: image, isAnimated: false, byteSize: item.byteSize), for: item.id)

            let hosting = SafeHostingView(pesto: ClipboardCard(item: item)
                .frame(width: 220, height: 220)
                .modelContainer(container))
            hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 220)
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 220, height: 220),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let raw = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
            return try #require(raw.usingColorSpace(.sRGB))
        }

        private static func solidRed(size: Int = 64) throws -> (image: NSImage, pngData: Data) {
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: size, height: size).fill()
            NSGraphicsContext.restoreGraphicsState()
            let data = try #require(rep.representation(using: .png, properties: [:]))
            return try (#require(NSImage(data: data)), data)
        }
    }
}
