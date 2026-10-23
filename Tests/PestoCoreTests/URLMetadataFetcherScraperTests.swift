// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("URLMetadataFetcher OpenGraph Scraper")
struct URLMetadataFetcherScraperTests {
    @Test("extracts og:image from standard property tag")
    func whenStandardOGImage_thenExtractsURL() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Tenor GIF</title>
            <meta property="og:image" content="https://media.tenor.com/images/12345/tenor.gif" />
            <meta property="og:title" content="Funny Cat" />
        </head>
        <body></body>
        </html>
        """
        let extracted = URLMetadataFetcher.extractOGImageURL(from: html)
        #expect(extracted == URL(string: "https://media.tenor.com/images/12345/tenor.gif"))
    }

    @Test("extracts og:image:secure_url when present")
    func whenSecureURL_thenExtractsURL() {
        let html = """
        <html>
        <head>
            <meta property="og:image:secure_url" content="https://media.tenor.com/secure.gif" />
        </head>
        </html>
        """
        let extracted = URLMetadataFetcher.extractOGImageURL(from: html)
        #expect(extracted == URL(string: "https://media.tenor.com/secure.gif"))
    }

    @Test("extracts inverted attribute order where content comes before property")
    func whenContentBeforeProperty_thenExtractsURL() {
        let html = """
        <html>
        <head>
            <meta content="https://example.com/preview.png" property="og:image" />
        </head>
        </html>
        """
        let extracted = URLMetadataFetcher.extractOGImageURL(from: html)
        #expect(extracted == URL(string: "https://example.com/preview.png"))
    }

    @Test("extracts twitter:image tag as fallback")
    func whenTwitterImagePresent_thenExtractsURL() {
        let html = """
        <html>
        <head>
            <meta name="twitter:image" content="https://pbs.twimg.com/media/abc.jpg" />
        </head>
        </html>
        """
        let extracted = URLMetadataFetcher.extractOGImageURL(from: html)
        #expect(extracted == URL(string: "https://pbs.twimg.com/media/abc.jpg"))
    }

    @Test("returns nil for HTML without image meta tags or with invalid URLs")
    func whenNoImageTags_thenReturnsNil() {
        let html = "<html><head><title>No Image</title></head><body>Hello</body></html>"
        #expect(URLMetadataFetcher.extractOGImageURL(from: html) == nil)

        let invalidHtml = #"<html><head><meta property="og:image" content="not-a-url" /></head></html>"#
        #expect(URLMetadataFetcher.extractOGImageURL(from: invalidHtml) == nil)

        let relativeHtml = #"<html><head><meta property="og:image" content="/relative/path.png" /></head></html>"#
        #expect(URLMetadataFetcher.extractOGImageURL(from: relativeHtml) == nil)
    }
}
