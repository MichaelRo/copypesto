// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Whether a card's header names the app a clip came from")
struct CardHeaderNamingTests {
    private func item(_ type: ClipboardType = .text, app: String?, remote: Bool = false) -> ClipboardItem {
        let clip = ClipboardItem(
            type: type, sourceAppName: app, previewText: "hello", contentHash: UUID().uuidString, byteSize: 5,
            deviceID: "device", sequenceNumber: 1
        )
        clip.isRemote = remote
        return clip
    }

    @Test("a plain text clip names its app")
    func whenTextHasAnApp_thenTheHeaderNamesIt() {
        #expect(item(app: "Mail").headerNamesTheApp)
    }

    @Test("an app macOS could not name is not worth a header, so the card says what the clip is")
    func whenTheAppIsUnknown_thenTheHeaderFallsBackToTheKind() {
        #expect(!item(app: SourceAppRecord.unknownDisplayName).headerNamesTheApp)
        #expect(!item(app: nil).headerNamesTheApp)
    }

    @Test("other kinds and clips from another device keep their own label")
    func whenNotPlainTextFromThisMac_thenTheKindShows() {
        #expect(!item(.url, app: "Safari").headerNamesTheApp)
        #expect(!item(app: "Mail", remote: true).headerNamesTheApp)
    }

    @Test("a title the person gave wins over the app")
    func whenTitled_thenTheTitleWins() {
        let clip = item(app: "Mail")
        clip.customTitle = "Invoice"
        #expect(!clip.headerNamesTheApp)
    }

    @Test("the app's name is offered only when macOS could name it")
    func knownSourceAppName_skipsTheFallback() {
        #expect(item(app: "Mail").knownSourceAppName == "Mail")
        #expect(item(app: SourceAppRecord.unknownDisplayName).knownSourceAppName == nil)
        #expect(item(app: nil).knownSourceAppName == nil)
    }
}
