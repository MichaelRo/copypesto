// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI
import Testing
@testable import Pesto

@Observable
@MainActor
private final class CardEvictionHostModel {
    var isFocused = false
    var isShown = true
}

private struct CardEvictionHostView: View {
    let item: ClipboardItem
    let container: ModelContainer
    let model: CardEvictionHostModel

    var body: some View {
        Group {
            if model.isShown {
                ClipboardCard(item: item, isFocused: model.isFocused)
                    .equatable()
            } else {
                Color.clear
            }
        }
        .frame(width: 220, height: 220)
        .modelContainer(container)
    }
}

extension HostedGlobals {
    @Suite("ClipboardCard thumbnail retention", .serialized)
    @MainActor
    final class ClipboardCardThumbnailEvictionTests {
        private func makeSolidRedImage(size: Int = 64) throws -> (image: NSImage, pngData: Data) {
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: size,
                pixelsHigh: size,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: size, height: size).fill()
            NSGraphicsContext.restoreGraphicsState()

            let data = try #require(rep.representation(using: .png, properties: [:]))
            let image = try #require(NSImage(data: data))
            return (image, data)
        }

        private func centerColor(of view: NSView) throws -> NSColor {
            view.layoutSubtreeIfNeeded()
            let bounds = view.bounds
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: bounds))
            view.cacheDisplay(in: bounds, to: rep)
            let raw = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
            return try #require(raw.usingColorSpace(.sRGB))
        }

        private func pumpMainRunLoop(for duration: TimeInterval = 0.15) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
        }

        @Test("when ThumbnailCache evicts an on-screen card's entry and the card re-renders, it keeps its picture")
        func whenThumbnailCacheEvictsOnScreenCard_thenCardRetainsPictureOnRerender() throws {
            ThumbnailCache.shared.clear()
            defer { ThumbnailCache.shared.clear() }

            let container = try ModelContainerSetup.makeInMemory()
            let context = ModelContext(container)
            let (image, pngData) = try makeSolidRedImage()
            let item = ClipboardItem(
                type: .image,
                sourceAppName: "Preview",
                previewText: "Image",
                contentHash: UUID().uuidString,
                byteSize: pngData.count,
                deviceID: "test-device",
                sequenceNumber: 1
            )
            item.blob = ClipboardBlob(
                encryptedData: Data(),
                nonceData: Data(),
                mimeType: "public.png"
            )
            context.insert(item)
            try context.save()

            ThumbnailCache.shared.store(
                .init(image: image, isAnimated: false, byteSize: item.byteSize),
                for: item.id
            )

            let model = CardEvictionHostModel()
            let hosting = SafeHostingView(pesto: CardEvictionHostView(
                item: item,
                container: container,
                model: model
            ))
            hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 220)

            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 220, height: 220),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFront(nil)
            defer { window.orderOut(nil) }

            pumpMainRunLoop()
            let initial = try centerColor(of: hosting)
            #expect(initial.redComponent > 0.7)
            #expect(initial.greenComponent < 0.3)
            #expect(initial.blueComponent < 0.3)

            ThumbnailCache.shared.remove(for: item.id)
            #expect(ThumbnailCache.shared.entry(for: item.id, byteSize: item.byteSize) == nil)

            // Re-evaluating ClipboardCard.body (as happens on hover or focus) must not fall back to the placeholder.
            model.isFocused.toggle()
            pumpMainRunLoop()

            let afterEviction = try centerColor(of: hosting)
            #expect(afterEviction.redComponent > 0.7)
            #expect(afterEviction.greenComponent < 0.3)
            #expect(afterEviction.blueComponent < 0.3)
        }

        @Test("when an image card goes off-screen, releaseOffscreenThumbnail clears its retained picture")
        func whenCardDisappears_thenOffscreenThumbnailIsReleased() throws {
            ThumbnailCache.shared.clear()
            defer { ThumbnailCache.shared.clear() }

            let container = try ModelContainerSetup.makeInMemory()
            let context = ModelContext(container)
            let (image, pngData) = try makeSolidRedImage()
            let item = ClipboardItem(
                type: .image,
                sourceAppName: "Preview",
                previewText: "Image",
                contentHash: UUID().uuidString,
                byteSize: pngData.count,
                deviceID: "test-device",
                sequenceNumber: 1
            )
            item.blob = ClipboardBlob(
                encryptedData: Data(),
                nonceData: Data(),
                mimeType: "public.png"
            )
            context.insert(item)
            try context.save()

            ThumbnailCache.shared.store(
                .init(image: image, isAnimated: false, byteSize: item.byteSize),
                for: item.id
            )

            let model = CardEvictionHostModel()
            let hosting = SafeHostingView(pesto: CardEvictionHostView(
                item: item,
                container: container,
                model: model
            ))
            hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 220)

            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 220, height: 220),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFront(nil)
            defer { window.orderOut(nil) }

            pumpMainRunLoop()
            let initial = try centerColor(of: hosting)
            #expect(initial.redComponent > 0.7)

            model.isShown = false
            pumpMainRunLoop()

            ThumbnailCache.shared.remove(for: item.id)
            model.isShown = true
            pumpMainRunLoop()

            // With both the off-screen @State released and the cache empty (and no encrypted blob to decode),
            // the re-appearing card falls back to the placeholder rather than holding the old NSImage in memory.
            let afterReappear = try centerColor(of: hosting)
            #expect(afterReappear.redComponent - afterReappear.blueComponent < 0.2)
        }
    }
}
