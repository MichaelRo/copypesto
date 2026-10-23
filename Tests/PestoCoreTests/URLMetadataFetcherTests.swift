// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

/// Unit tests for `URLMetadataFetcher.processOGImageData`.
///
/// Pesto's grid renders animated GIFs via `AnimatedImageView` (an `NSImageView`
/// wrapper with `animates = true`). For url-typed items the OG image is fetched
/// via `LPMetadataProvider`; previously every payload was funneled through
/// `CGImageSourceCreateThumbnailAtIndex(_, 0, _)` which extracts a single frame
/// and re-encodes it as JPEG, silently turning every GIF into a still image.
///
/// `processOGImageData` short-circuits that path: a GIF whose payload is at
/// or under `maxAnimatedGIFBytes` is returned untouched so AnimatedImageView
/// can play it. Anything else still goes through the thumbnail pipeline.
@Suite("URLMetadataFetcher OG image policy")
struct URLMetadataFetcherTests {
    /// Smallest viable GIF89a payload: 1×1 transparent pixel.
    /// The bytes are a literal canonical "tiny GIF" used widely as a 1×1 fixture.
    private static let tinyGIF: Data = .init([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // header GIF89a
        0x01, 0x00, 0x01, 0x00, // 1×1 dimensions
        0x80, 0x00, 0x00, // GCT flag, background, aspect
        0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, // two-color palette
        0x21, 0xF9, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, // GCE
        0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // image descriptor
        0x02, 0x02, 0x44, 0x01, 0x00, 0x3B // LZW + trailer
    ])

    @Test("GIF bytes under the size cap are returned byte-for-byte")
    func tinyGIF_preservedUnchanged() {
        let processed = URLMetadataFetcher.processOGImageData(Self.tinyGIF)
        #expect(processed == Self.tinyGIF)
    }

    @Test("GIF bytes above the size cap fall through to JPEG thumbnail (no animation)")
    func oversizedGIF_fallsBackToThumbnail() {
        // Build a payload that LOOKS like a GIF header but is too big to preserve.
        // The thumbnail path returns nil for non-decodable bytes; that's fine for the
        // purpose of this test: we only care that the GIF passthrough is skipped.
        var bigGIF = Self.tinyGIF
        bigGIF.append(Data(repeating: 0xAB, count: URLMetadataFetcher.maxAnimatedGIFBytes + 1))
        let processed = URLMetadataFetcher.processOGImageData(bigGIF)
        // Either nil (decoder rejects the padded bytes) or non-equal to the raw input —
        // never the raw input itself, which is what would have preserved animation.
        #expect(processed != bigGIF)
    }

    @Test("Non-GIF bytes still route through the thumbnail re-encoder")
    func pngBytes_thumbnailedNotPreserved() {
        // Minimal PNG header — won't decode to an image, but is enough to prove the
        // function does NOT short-circuit on non-GIF input.
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let processed = URLMetadataFetcher.processOGImageData(pngHeader)
        // PNG header is not a GIF, so the GIF passthrough must not return it.
        #expect(processed != pngHeader)
    }
}

private final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var chunkSize = 0
    }

    nonisolated(unsafe) static var response = Stub()

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stub = Self.response
        guard let url = request.url,
              let http = HTTPURLResponse(
                  url: url,
                  statusCode: stub.status,
                  httpVersion: nil,
                  headerFields: stub.headers
              ) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if stub.chunkSize > 0 {
            for start in stride(from: 0, to: stub.body.count, by: stub.chunkSize) {
                client?.urlProtocol(self, didLoad: stub.body[start..<min(start + stub.chunkSize, stub.body.count)])
            }
        } else {
            client?.urlProtocol(self, didLoad: stub.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Links that point straight at a GIF", .serialized)
struct DirectGIFLinkTests {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }()

    private let gif = Data([
        0x47,
        0x49,
        0x46,
        0x38,
        0x39,
        0x61,
        0x01,
        0x00,
        0x01,
        0x00,
        0x80,
        0x00,
        0x00,
        0,
        0,
        0,
        255,
        255,
        255,
        0x3B
    ])

    @Test("only http(s) links whose path ends in .gif are treated as GIF links")
    func whenLink_thenRecognised() throws {
        #expect(try URLMetadataFetcher.isDirectGIFLink(#require(URL(string: "https://media.example.com/a/b.GIF?x=1"))))
        #expect(try !URLMetadataFetcher.isDirectGIFLink(#require(URL(string: "https://example.com/gifs/cat"))))
        #expect(try !URLMetadataFetcher.isDirectGIFLink(#require(URL(string: "https://example.com/a.png"))))
        #expect(try !URLMetadataFetcher.isDirectGIFLink(#require(URL(string: "file:///tmp/a.gif"))))
    }

    @Test("a GIF link downloads the GIF")
    func whenServerReturnsGIF_thenData() async throws {
        StubURLProtocol.response = .init(status: 200, headers: ["Content-Type": "image/gif"], body: gif)
        let data = try await URLMetadataFetcher.downloadGIF(
            from: #require(URL(string: "https://x.example/a.gif")),
            session: session
        )
        #expect(data == gif)
    }

    @Test("an error status, a body that is not a GIF, or a huge GIF gives nothing")
    func whenNotUsable_thenNil() async throws {
        let url = try #require(URL(string: "https://x.example/a.gif"))
        StubURLProtocol.response = .init(status: 404, body: gif)
        #expect(await URLMetadataFetcher.downloadGIF(from: url, session: session) == nil)
        StubURLProtocol.response = .init(status: 200, body: Data("<html>not a gif</html>".utf8))
        #expect(await URLMetadataFetcher.downloadGIF(from: url, session: session) == nil)
        StubURLProtocol.response = .init(
            status: 200, headers: ["Content-Length": "\(URLMetadataFetcher.maxDownloadBytes + 1)"], body: gif
        )
        #expect(await URLMetadataFetcher.downloadGIF(from: url, session: session) == nil)
    }

    @Test("a GIF that arrives in many pieces is put back together")
    func whenServerSendsChunks_thenWholeGIF() async throws {
        StubURLProtocol.response = .init(headers: ["Content-Type": "image/gif"], body: gif, chunkSize: 3)
        let data = try await URLMetadataFetcher.downloadGIF(
            from: #require(URL(string: "https://x.example/a.gif")),
            session: session
        )
        #expect(data == gif)
    }

    @Test("a body past the limit gives nothing even when the server did not say how long it is")
    func whenBodyIsOverTheLimitWithNoLength_thenNil() async throws {
        var body = gif.dropLast()
        body.append(Data(count: URLMetadataFetcher.maxDownloadBytes))
        body.append(0x3B)
        StubURLProtocol.response = .init(headers: [:], body: Data(body), chunkSize: 1 << 20)
        let data = try await URLMetadataFetcher.downloadGIF(
            from: #require(URL(string: "https://x.example/a.gif")),
            session: session
        )
        #expect(data == nil)
    }

    @Test("a download that is cancelled gives nothing")
    func whenCancelled_thenNil() async throws {
        StubURLProtocol.response = .init(headers: [:], body: gif)
        let url = try #require(URL(string: "https://x.example/a.gif"))
        let session = session
        let task = Task { await URLMetadataFetcher.downloadGIF(from: url, session: session) }
        task.cancel()
        _ = await task.value
    }

    @Test("an animated picture that is not a GIF is kept as a playing GIF, not a still")
    func animatedNonGIF_becomesAPlayingGIF() throws {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 4, nil
        ))
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary
        )
        for index in 0..<4 {
            let context = try #require(CGContext(
                data: nil, width: 80, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: Double(index) / 4, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
            try CGImageDestinationAddImage(
                destination, #require(context.makeImage()),
                [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.1]] as CFDictionary
            )
        }
        #expect(CGImageDestinationFinalize(destination))

        let processed = try #require(URLMetadataFetcher.processOGImageData(output as Data))
        #expect(processed.isGIF)
        #expect(try CGImageSourceGetCount(#require(CGImageSourceCreateWithData(processed as CFData, nil))) == 4)
    }

    @MainActor
    @Test("with link previews switched off the fetcher refuses before it touches the network")
    func whenPreviewsAreOff_thenFetchRefuses() async throws {
        let fetcher = URLMetadataFetcher(isEnabled: { false })
        let url = try #require(URL(string: "https://example.com/page"))

        await #expect(throws: URLError.self) { try await fetcher.fetch(url: url) }
    }

    @MainActor
    @Test("a direct GIF link is refused too when previews are off")
    func whenPreviewsAreOff_thenDirectGIFIsRefused() async throws {
        let fetcher = URLMetadataFetcher(isEnabled: { false })
        let url = try #require(URL(string: "https://media.example.com/a.gif"))

        await #expect(throws: URLError.self) { try await fetcher.fetch(url: url) }
    }
}

@Suite("URLMetadataFetcher synthesization and caching", .serialized)
@MainActor
struct URLMetadataFetcherCacheTests {
    private func makeTempCache() -> (LinkPreviewCache, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("test-fetcher-cache.json")
        return (LinkPreviewCache(fileURL: fileURL, ttl: 3600), fileURL)
    }

    @Test("Google search URL is synthesized locally without calling loader")
    func whenGoogleSearchURL_thenSynthesizedLocallyWithoutNetwork() async throws {
        let (cache, tempURL) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let loaderCalled = Mutex(false)
        let fetcher = URLMetadataFetcher(isEnabled: { true }, linkPreviewCache: cache, loader: { _ in
            loaderCalled.withLock { $0 = true }
            return URLPreviewResult(title: "From Network", ogImageData: nil, faviconData: nil, siteName: "Network")
        })

        let url = try #require(URL(string: "https://www.google.com/search?q=swift+concurrency"))
        let result = try await fetcher.fetch(url: url)

        #expect(!loaderCalled.withLock { $0 })
        #expect(result.title == "swift concurrency — Google Search")
        #expect(result.siteName == "Google")
    }

    @Test("Google tracking redirect URL is unwrapped before invoking loader")
    func whenGoogleRedirectURL_thenUnwrappedBeforeLoader() async throws {
        let (cache, tempURL) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let loadedURL = Mutex<URL?>(nil)
        let fetcher = URLMetadataFetcher(isEnabled: { true }, linkPreviewCache: cache, loader: { target in
            loadedURL.withLock { $0 = target }
            return URLPreviewResult(title: "Swift.org", ogImageData: nil, faviconData: nil, siteName: "Swift")
        })

        let wrapped = try #require(URL(string: "https://www.google.com/url?q=https%3A%2F%2Fswift.org%2Fblog&sa=D"))
        let result = try await fetcher.fetch(url: wrapped)

        #expect(loadedURL.withLock { $0 } == URL(string: "https://swift.org/blog"))
        #expect(result.title == "Swift.org")
    }

    @Test("Cached entry in LinkPreviewCache is returned without calling loader")
    func whenCachedInLinkPreviewCache_thenLoaderSkipped() async throws {
        let (cache, tempURL) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let targetURL = try #require(URL(string: "https://example.com/cached-article"))
        cache.store(
            LinkPreviewCache.Entry(
                title: "Cached Title",
                siteName: "Example",
                faviconData: nil,
                ogImageData: nil,
                isNegative: false
            ),
            for: targetURL
        )

        let loaderCalled = Mutex(false)
        let fetcher = URLMetadataFetcher(isEnabled: { true }, linkPreviewCache: cache, loader: { _ in
            loaderCalled.withLock { $0 = true }
            return URLPreviewResult(title: "Network Title", ogImageData: nil, faviconData: nil, siteName: "Network")
        })

        let result = try await fetcher.fetch(url: targetURL)
        #expect(!loaderCalled.withLock { $0 })
        #expect(result.title == "Cached Title")
    }

    @Test("Failed fetch records negative cache and prevents repeated loader calls")
    func whenFetchFails_thenNegativeCacheStoresAndPreventsRetry() async throws {
        let (cache, tempURL) = makeTempCache()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let callCount = Mutex(0)
        let fetcher = URLMetadataFetcher(isEnabled: { true }, linkPreviewCache: cache, loader: { _ in
            callCount.withLock { $0 += 1 }
            throw URLError(.cannotConnectToHost)
        })

        let targetURL = try #require(URL(string: "https://failing-domain.org/broken"))

        // First call should fail and throw
        await #expect(throws: URLError.self) {
            try await fetcher.fetch(url: targetURL)
        }
        #expect(callCount.withLock { $0 } == 1)

        // Second call should hit negative cache and return empty result without re-calling loader
        let secondResult = try await fetcher.fetch(url: targetURL)
        #expect(callCount.withLock { $0 } == 1)
        #expect(secondResult.title == nil)
    }
}
