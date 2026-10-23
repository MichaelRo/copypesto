// SPDX-License-Identifier: MIT
import Foundation
import Synchronization
import Testing
@testable import PestoCore

private final class RecordingProtocol: URLProtocol {
    nonisolated static let requested = Mutex<[URL]>([])
    nonisolated static let pageBody = Mutex(Data())

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else
        {
            return
        }
        Self.requested.withLock { $0.append(url) }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.pageBody.withLock { $0 })
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("The og:image address read out of a page is vetted like the page itself (R-03)", .serialized)
struct URLMetadataFetcherOGImageTests {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingProtocol.self]
        return URLSession(configuration: configuration)
    }()

    private func scrape(imageAddress: String) async throws -> [URL] {
        RecordingProtocol.requested.withLock { $0 = [] }
        let html = "<html><head><meta property='og:image' content='\(imageAddress)'></head></html>"
        RecordingProtocol.pageBody.withLock { $0 = Data(html.utf8) }
        let page = try #require(URL(string: "https://page.example/article"))
        _ = await URLMetadataFetcher.scrapeOGImage(from: page, session: session)
        return RecordingProtocol.requested.withLock { $0 }
    }

    @Test("an image on a private or local address is never requested", arguments: [
        "http://10.0.0.1/x.png", "http://127.0.0.1:18082/internal-admin?token=1", "http://192.168.0.1/admin/reset",
        "http://localhost/x.png", "http://printer.local/x.png", "https://img.example/x.png?token=abc"
    ])
    func whenImageAddressIsNotEligible_thenOnlyThePageIsRequested(address: String) async throws {
        let requested = try await scrape(imageAddress: address)
        #expect(requested.map(\.absoluteString) == ["https://page.example/article"], "\(requested)")
    }

    @Test("control: an image on a public address is requested")
    func whenImageAddressIsPublic_thenItIsRequested() async throws {
        let requested = try await scrape(imageAddress: "https://img.example/cover.png")
        #expect(requested.map(\.absoluteString) == ["https://page.example/article", "https://img.example/cover.png"])
    }
}
