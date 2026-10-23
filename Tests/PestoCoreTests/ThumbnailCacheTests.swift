// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("Thumbnail cache")
@MainActor
struct ThumbnailCacheTests {
    private func image(side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side))
    }

    @Test("a picture that was stored comes back for the same clip and not for another")
    func storeAndFind() {
        let cache = ThumbnailCache()
        let id = UUID()
        cache.store(.init(image: image(side: 10), isAnimated: true, byteSize: 7), for: id)

        #expect(cache.entry(for: id, byteSize: 7)?.isAnimated == true)
        #expect(cache.entry(for: UUID(), byteSize: 7) == nil)
    }

    @Test("clearing forgets every picture")
    func clearForgets() {
        let cache = ThumbnailCache()
        let ids = (0..<5).map { _ in UUID() }
        for id in ids {
            cache.store(.init(image: image(side: 10), isAnimated: false, byteSize: 7), for: id)
        }

        cache.clear()

        #expect(ids.allSatisfy { cache.entry(for: $0, byteSize: 7) == nil })
    }

    @Test("the byte limit keeps memory bounded: far more pictures than fit do not all stay")
    func byteLimitEvicts() {
        let cache = ThumbnailCache(byteLimit: 400_000, countLimit: 600)
        let ids = (0..<40).map { _ in UUID() }
        for id in ids {
            cache.store(.init(image: image(side: 100), isAnimated: false, byteSize: 7), for: id)
        }

        let kept = ids.count(where: { cache.entry(for: $0, byteSize: 7) != nil })
        #expect(kept < ids.count)
        #expect(kept > 0)
    }

    @Test("a still picture that has become its GIF is not served from the cache")
    func staleSizeIsNotOffered() {
        let cache = ThumbnailCache()
        let id = UUID()
        cache.store(.init(image: image(side: 10), isAnimated: false, byteSize: 7), for: id)

        #expect(cache.entry(for: id, byteSize: 7) != nil)
        #expect(cache.entry(for: id, byteSize: 9) == nil)
    }

    @Test("the default cache keeps at most 48 MB of 480-pixel thumbnails, so scrolling over pictures stays in budget")
    func defaultCacheHoldsAtMost48MB() {
        let cache = ThumbnailCache()
        let ids = (0..<300).map { _ in UUID() }
        for id in ids {
            cache.store(
                .init(image: NSImage(size: NSSize(width: 480, height: 300)), isAnimated: false, byteSize: 7), for: id
            )
        }

        let kept = ids.count(where: { cache.entry(for: $0, byteSize: 7) != nil })
        #expect(kept * 480 * 300 * 4 <= 50 * 1024 * 1024, "kept \(kept) thumbnails")
        #expect(kept > 20, "the cache must still hold more than a screen of cards")
    }
}
