// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("SearchEnginePreviewSynthesizer")
struct SearchEnginePreviewSynthesizerTests {
    @Test("synthesizes Google Search query preview")
    func whenGoogleSearchQuery_thenSynthesizes() throws {
        let url = try #require(URL(string: "https://www.google.com/search?q=pesto+recipe&client=safari"))
        let preview = SearchEnginePreviewSynthesizer.synthesize(url)
        #expect(preview?.title == "pesto recipe — Google Search")
        #expect(preview?.siteName == "Google")
    }

    @Test("synthesizes international Google Search query preview")
    func whenInternationalGoogleSearchQuery_thenSynthesizes() throws {
        let url = try #require(URL(string: "https://www.google.co.uk/search?q=basil+pine+nuts"))
        let preview = SearchEnginePreviewSynthesizer.synthesize(url)
        #expect(preview?.title == "basil pine nuts — Google Search")
        #expect(preview?.siteName == "Google")
    }

    @Test("synthesizes Bing Search query preview")
    func whenBingSearchQuery_thenSynthesizes() throws {
        let url = try #require(URL(string: "https://www.bing.com/search?q=swift+concurrency"))
        let preview = SearchEnginePreviewSynthesizer.synthesize(url)
        #expect(preview?.title == "swift concurrency — Bing Search")
        #expect(preview?.siteName == "Bing")
    }

    @Test("synthesizes DuckDuckGo query preview")
    func whenDuckDuckGoQuery_thenSynthesizes() throws {
        let url = try #require(URL(string: "https://duckduckgo.com/?q=macOS+sequoia&t=h_"))
        let preview = SearchEnginePreviewSynthesizer.synthesize(url)
        #expect(preview?.title == "macOS sequoia — DuckDuckGo")
        #expect(preview?.siteName == "DuckDuckGo")
    }

    @Test("synthesizes Google Docs and Drive preview")
    func whenGoogleDocsAndDrive_thenSynthesizes() throws {
        let doc = try #require(URL(string: "https://docs.google.com/document/d/1234567890/edit"))
        let docPreview = SearchEnginePreviewSynthesizer.synthesize(doc)
        #expect(docPreview?.siteName == "Google Docs")
        #expect(docPreview?.title == "Google Docs Document")

        let sheet = try #require(URL(string: "https://docs.google.com/spreadsheets/d/abcdef/edit"))
        let sheetPreview = SearchEnginePreviewSynthesizer.synthesize(sheet)
        #expect(sheetPreview?.siteName == "Google Sheets")
        #expect(sheetPreview?.title == "Google Sheets Spreadsheet")

        let drive = try #require(URL(string: "https://drive.google.com/drive/folders/xyz"))
        let drivePreview = SearchEnginePreviewSynthesizer.synthesize(drive)
        #expect(drivePreview?.siteName == "Google Drive")
    }

    @Test("synthesizes Google Maps, Images, and home domain previews on-device")
    func whenGoogleServices_thenSynthesizesLocallyWithoutNetwork() throws {
        let maps = try #require(URL(string: "https://www.google.com/maps/place/San+Francisco"))
        let mapsPreview = SearchEnginePreviewSynthesizer.synthesize(maps)
        #expect(mapsPreview?.title == "Google Maps")
        #expect(mapsPreview?.siteName == "Google Maps")

        let images = try #require(URL(string: "https://images.google.com/imghp"))
        let imagesPreview = SearchEnginePreviewSynthesizer.synthesize(images)
        #expect(imagesPreview?.title == "Google Images")
        #expect(imagesPreview?.siteName == "Google Images")

        let home = try #require(URL(string: "https://www.google.com/"))
        let homePreview = SearchEnginePreviewSynthesizer.synthesize(home)
        #expect(homePreview?.title == "Google")
        #expect(homePreview?.siteName == "Google")

        let intl = try #require(URL(string: "https://www.google.co.il/"))
        let intlPreview = SearchEnginePreviewSynthesizer.synthesize(intl)
        #expect(intlPreview?.title == "Google")
        #expect(intlPreview?.siteName == "Google")
    }

    @Test("returns nil for ordinary websites")
    func whenOrdinaryWebsite_thenReturnsNil() throws {
        let url = try #require(URL(string: "https://en.wikipedia.org/wiki/Pesto"))
        #expect(SearchEnginePreviewSynthesizer.synthesize(url) == nil)
    }

    @Test("rejects attacker domains spoofing Google subdomains")
    func whenAttackerDomainWithGoogleSubdomain_thenReturnsNil() throws {
        let spoof1 = try #require(URL(string: "https://login.google.com.attacker.com/login"))
        #expect(SearchEnginePreviewSynthesizer.synthesize(spoof1) == nil)

        let spoof2 = try #require(URL(string: "https://phishing.google.com.evil.org/"))
        #expect(SearchEnginePreviewSynthesizer.synthesize(spoof2) == nil)

        let spoof3 = try #require(URL(string: "https://fake-google.com/search?q=test"))
        #expect(SearchEnginePreviewSynthesizer.synthesize(spoof3) == nil)
    }
}
