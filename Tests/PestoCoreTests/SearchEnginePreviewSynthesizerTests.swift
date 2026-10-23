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

    @Test("returns nil for ordinary websites")
    func whenOrdinaryWebsite_thenReturnsNil() throws {
        let url = try #require(URL(string: "https://en.wikipedia.org/wiki/Pesto"))
        #expect(SearchEnginePreviewSynthesizer.synthesize(url) == nil)
    }
}
