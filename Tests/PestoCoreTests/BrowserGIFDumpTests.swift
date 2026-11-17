// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import Testing
@testable import PestoCore

private final class BrowserGIFStubURLProtocol: URLProtocol {
    struct Stub {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
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
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite("Browser Copy Image GIF dumps and URLMetadataFetcher policy", .serialized)
struct BrowserGIFDumpTests {
    private static let tinyGIF: Data = .init([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
        0x01, 0x00, 0x01, 0x00,
        0x80, 0x00, 0x00,
        0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
        0x21, 0xF9, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0x02, 0x02, 0x44, 0x01, 0x00, 0x3B
    ])

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserGIFStubURLProtocol.self]
        return URLSession(configuration: config)
    }()

    @Test("Chrome, Arc, and Edge Copy Image dumps yield animated sourceImageURL")
    func whenBrowserCopyImageDumps_thenExtractsAnimatedURL() async throws {
        struct GIFCase { let file: String
            let expectedHost: String
            let expectedExt: String
        }
        let cases = [
            GIFCase(file: "chrome-copy-image-gif.json", expectedHost: "media.giphy.com", expectedExt: "gif"),
            GIFCase(file: "arc-copy-image-gif.json", expectedHost: "media.tenor.com", expectedExt: "gif"),
            GIFCase(file: "edge-copy-image-webp.json", expectedHost: "media.giphy.com", expectedExt: "webp")
        ]

        for entry in cases {
            let fixture = try PasteboardDumpFixture.load(named: entry.file)
            let board = FakePasteboard()
            let watcher = PasteboardWatcher(
                pasteboard: board,
                frontmostProvider: FakeFrontmost(bundleID: fixture.sourceBundleID)
            )
            let collector = CaptureCollector()
            await watcher.onCapture { collector.append($0) }
            fixture.write(to: board)
            await watcher.tick()

            let captured = try #require(collector.first, "expected capture for \(entry.file)")
            let sourceURL = try #require(captured.sourceImageURL, "expected sourceImageURL for \(entry.file)")
            #expect(sourceURL.host == entry.expectedHost)
            #expect(sourceURL.pathExtension.lowercased() == entry.expectedExt)
        }
    }

    @Test("HTTPS GIF download succeeds via URLProtocol stub")
    func whenHTTPSGIF_thenDownloaded() async throws {
        BrowserGIFStubURLProtocol.response = .init(
            status: 200,
            headers: ["Content-Type": "image/gif"],
            body: Self.tinyGIF
        )
        let url = try #require(URL(string: "https://media.giphy.com/media/abc123/giphy.gif"))
        let data = await URLMetadataFetcher.downloadGIF(from: url, session: session)
        #expect(data == Self.tinyGIF)
    }

    @Test("loopback and non-HTTPS URLs are rejected by LinkPreviewEligibility and ImageSourceAddress")
    func whenLoopbackOrNonHTTPS_thenRejected() throws {
        let loopback = try #require(URL(string: "https://127.0.0.1/a.gif"))
        let localhost = try #require(URL(string: "http://localhost/a.gif"))
        let ftpGIF = try #require(URL(string: "ftp://media.giphy.com/a.gif"))
        #expect(!LinkPreviewEligibility.isEligible(loopback))
        #expect(!LinkPreviewEligibility.isEligible(localhost))
        #expect(!LinkPreviewEligibility.isEligible(ftpGIF))

        let html = "<img src=\"http://127.0.0.1/secret.gif\"><img src=\"http://example.com/a.gif\">"
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: html) == nil)
    }

    @Test("404 status, non-GIF body, and oversized payload (> maxDownloadBytes) are refused")
    func when404NonGIFOrOversized_thenNil() async throws {
        let url = try #require(URL(string: "https://media.giphy.com/media/abc123/giphy.gif"))

        BrowserGIFStubURLProtocol.response = .init(status: 404, body: Self.tinyGIF)
        #expect(await URLMetadataFetcher.downloadGIF(from: url, session: session) == nil)

        BrowserGIFStubURLProtocol.response = .init(status: 200, body: Data("<html>not a gif</html>".utf8))
        #expect(await URLMetadataFetcher.downloadGIF(from: url, session: session) == nil)

        BrowserGIFStubURLProtocol.response = .init(
            status: 200,
            headers: ["Content-Length": "\(URLMetadataFetcher.maxDownloadBytes + 1)"],
            body: Self.tinyGIF
        )
        #expect(await URLMetadataFetcher.downloadGIF(from: url, session: session) == nil)
    }
}
