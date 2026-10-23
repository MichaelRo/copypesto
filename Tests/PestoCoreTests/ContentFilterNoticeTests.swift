// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Content filter notice")
struct ContentFilterNoticeTests {
    @Test("with picture screening available, the note says pictures are screened, best-effort")
    func whenAvailable_thenMentionsScreening() {
        let text = ContentFilterNotice.text(pictureScreeningAvailable: true)
        #expect(text.contains("screened"))
        #expect(text.contains("best-effort"))
        #expect(text.contains("Mark as Sensitive"))
    }

    @Test("without Apple Intelligence, the note says only links are filtered and how to mark pictures")
    func whenUnavailable_thenSaysOnlyLinksAreFiltered() {
        let text = ContentFilterNotice.text(pictureScreeningAvailable: false)
        #expect(text.contains("only links"))
        #expect(text.contains("Apple Intelligence"))
        #expect(text.contains("Mark as Sensitive"))
        #expect(!text.contains("are screened by"))
    }

    @Test("both notes explain blur, hide and show, and that nothing leaves the Mac")
    func whenEitherState_thenModesExplained() {
        for available in [true, false] {
            let text = ContentFilterNotice.text(pictureScreeningAvailable: available)
            #expect(text.contains("Blur") && text.contains("Hide") && text.contains("Show"))
            #expect(text.contains("Nothing leaves your device"))
        }
    }
}
