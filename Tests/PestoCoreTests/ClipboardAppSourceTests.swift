// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Clipboard app sources")
struct ClipboardAppSourceTests {
    @Test("each source names its app and starts in that app's own folder")
    func defaultLocations() {
        #expect(ClipboardAppSource.maccy.name == "Maccy")
        #expect(ClipboardAppSource.alfred.name == "Alfred")
        #expect(ClipboardAppSource.cleanclip.name == "CleanClip")
        #expect(ClipboardAppSource.pastenow.name == "PasteNow")
        #expect(ClipboardAppSource.copyclip.name == "CopyClip")
        #expect(ClipboardAppSource.pastepal.name == "PastePal")
        #expect(ClipboardAppSource.pastebot.name == "Pastebot")
        #expect(ClipboardAppSource.clipy.name == "Clipy")
        #expect(ClipboardAppSource.flycut.name == "Flycut")
        #expect(ClipboardAppSource.unclutter.name == "Unclutter")
        #expect(ClipboardAppSource.maccy.defaultDatabaseURL == MaccyLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.alfred.defaultDatabaseURL == AlfredLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.cleanclip.defaultDatabaseURL == CleanClipLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.pastenow.defaultDatabaseURL == PasteNowLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.copyclip.defaultDatabaseURL == CopyClipLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.pastepal.defaultDatabaseURL == PastePalLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.pastebot.defaultDatabaseURL == PastebotLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.clipy.defaultDatabaseURL == ClipyLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.flycut.defaultDatabaseURL == FlycutLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.unclutter.defaultDatabaseURL == UnclutterLibraryReader.defaultDatabaseURL)
        #expect(ClipboardAppSource.unclutter.canChooseDirectories == true)
        #expect(ClipboardAppSource.maccy.canChooseDirectories == false)
    }

    @Test("a missing file is reported as not found, whichever app it is read for")
    func missingFile() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).sqlite")
        for source in ClipboardAppSource.allCases {
            #expect(throws: ClipboardAppLibraryReader.ReadError.notFound) { try source.read(databaseAt: missing) }
        }
    }
}
