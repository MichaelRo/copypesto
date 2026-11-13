// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import Testing
@testable import PestoCore

/// Answers each address with its own body and counts the requests, so a test can say which pages were read twice.
private final class PerAddressProtocol: URLProtocol {
    nonisolated(unsafe) static var bodies: [String: (type: String, data: Data)] = [:]
    nonisolated(unsafe) static var requested: [String] = []

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.requested.append(url.absoluteString)
        let hit = Self.bodies[url.absoluteString]
        let http = HTTPURLResponse(
            url: url, statusCode: hit == nil ? 404 : 200, httpVersion: nil,
            headerFields: ["Content-Type": hit?.type ?? "text/plain"]
        )
        if let http { client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: hit?.data ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite("A page whose picture is a GIF shows the GIF", .serialized)
struct PageGIFPreviewTests {
    private let animated = SeedFixtures.animatedGIFData(side: 64)
    private let still = Self.stillPicture(side: 64)

    private nonisolated static func stillPicture(side: Int) -> Data {
        let gif = SeedFixtures.animatedGIFData(side: side)
        guard let source = CGImageSourceCreateWithData(gif as CFData, nil),
              let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return Data() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, frame, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : Data()
    }

    private func fetcher() -> URLMetadataFetcher {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PerAddressProtocol.self]
        PerAddressProtocol.requested = []
        return URLMetadataFetcher(
            isEnabled: { true }, linkPreviewCache: nil, session: URLSession(configuration: configuration),
            loader: { _ in URLPreviewResult(
                title: "Funny cat",
                ogImageData: Self.stillPicture(side: 64),
                faviconData: nil,
                siteName: "tenor.com"
            ) }
        )
    }

    private func frameCount(_ data: Data?) -> Int {
        data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.map(CGImageSourceGetCount) ?? 0
    }

    @Test("a Tenor-style page: LinkPresentation's still is replaced by the page's animated picture")
    func whenPageNamedForGIF_thenTheAnimationReplacesTheStill() async throws {
        PerAddressProtocol.bodies = [
            "https://tenor.com/view/cat-gif-5270302586453863905": (
                "text/html",
                Data("<meta property=\"og:image\" content=\"https://media.tenor.com/abc/tenor.gif\">".utf8)
            ),
            "https://media.tenor.com/abc/tenor.gif": ("image/gif", animated)
        ]
        let result = try await fetcher()
            .fetch(url: #require(URL(string: "https://tenor.com/view/cat-gif-5270302586453863905")))

        #expect(result.ogImageData?.isGIF == true)
        #expect(frameCount(result.ogImageData) > 1, "the preview is a GIF with one frame: it will not move")
        #expect(result.title == "Funny cat")
    }

    @Test("a page not named for a GIF is read once, by LinkPresentation alone")
    func whenPageIsOrdinary_thenNoSecondRequest() async throws {
        PerAddressProtocol.bodies = [:]
        let result = try await fetcher().fetch(url: #require(URL(string: "https://example.com/recipes/pesto")))

        #expect(PerAddressProtocol.requested.isEmpty)
        #expect(result.ogImageData?.isGIF != true)
    }

    @Test("a GIF page whose picture is not a GIF keeps the still it had")
    func whenPicturesIsNotAGIF_thenTheStillStays() async throws {
        PerAddressProtocol.bodies = [
            "https://tenor.com/view/cat-gif-1": (
                "text/html", Data("<meta property=\"og:image\" content=\"https://media.tenor.com/abc/tenor.png\">".utf8)
            ),
            "https://media.tenor.com/abc/tenor.png": ("image/png", still)
        ]
        let result = try await fetcher().fetch(url: #require(URL(string: "https://tenor.com/view/cat-gif-1")))

        #expect(result.ogImageData?.isGIF != true)
        #expect(result.ogImageData != nil)
    }
}
