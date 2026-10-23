// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("File clips")
struct FileClipTests {
    private let a = URL(fileURLWithPath: "/Users/me/Documents/basil recipe.pdf")
    private let b = URL(fileURLWithPath: "/Users/me/Documents/pine-nuts.zip")

    @Test("several files round-trip through the stored text, one per line, in order")
    func whenEncoded_thenDecodedInOrder() {
        let text = FileClip.encode([a, b])
        #expect(text.split(separator: "\n").count == 2)
        #expect(FileClip.urls(from: text) == [a, b])
    }

    @Test("a single file is stored exactly as before, so existing clips keep working")
    func whenOneFile_thenPlainURLString() {
        #expect(FileClip.encode([a]) == a.absoluteString)
        #expect(FileClip.urls(from: a.absoluteString) == [a])
    }

    @Test("blank lines and things that are not file URLs are ignored")
    func whenNoise_thenSkipped() {
        let text = "\n\(a.absoluteString)\nhttps://example.com\n\n"
        #expect(FileClip.urls(from: text) == [a])
        #expect(FileClip.urls(from: "not a url").isEmpty)
    }

    @Test("the card summary names the file and its folder, or counts a group")
    func whenSummarised_thenNameAndFolder() {
        let one = FileClip.summary(of: FileClip.encode([a]))
        #expect(one.title == "basil recipe.pdf")
        #expect(one.subtitle == "Documents")
        #expect(one.count == 1)
        let two = FileClip.summary(of: FileClip.encode([a, b]))
        #expect(two.title == "2 files")
        #expect(two.subtitle == "basil recipe.pdf, pine-nuts.zip")
        #expect(two.count == 2)
    }

    @Test("a long list is shortened with a count of the rest")
    func whenManyFiles_thenSubtitleShortened() {
        let urls = (1...6).map { URL(fileURLWithPath: "/tmp/f\($0).txt") }
        let summary = FileClip.summary(of: FileClip.encode(urls))
        #expect(summary.title == "6 files")
        #expect(summary.subtitle == "f1.txt, f2.txt and 4 more")
    }

    @Test("a file that is gone is reported as missing, one that exists is not")
    func whenChecked_thenMissingDetected() throws {
        let existing = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: existing)
        defer { try? FileManager.default.removeItem(at: existing) }
        let gone = existing.deletingLastPathComponent().appendingPathComponent("gone-\(UUID().uuidString).txt")

        #expect(FileClip.missing(in: [existing, gone]) == [gone])
        #expect(FileClip.missing(in: [existing]).isEmpty)
    }

    @Test("VoiceOver hears the file name and folder, and whether the file is gone, never the raw path")
    func whenSpoken_thenNamesAndState() {
        let one = FileClip.encode([a])
        #expect(FileClip.spokenDescription(of: one, missingCount: 0) == "basil recipe.pdf in Documents")
        #expect(FileClip
            .spokenDescription(of: one, missingCount: 1) == "basil recipe.pdf in Documents, moved or deleted")
        let two = FileClip.encode([a, b])
        #expect(FileClip.spokenDescription(of: two, missingCount: 0) == "2 files: basil recipe.pdf, pine-nuts.zip")
        #expect(FileClip.spokenDescription(of: two, missingCount: 2).hasSuffix(", 2 moved or deleted"))
    }

    @Test("a folder is described as a folder, not a document")
    func whenDirectory_thenFlagged() {
        #expect(FileClip.isFolder(URL(fileURLWithPath: NSTemporaryDirectory())))
        #expect(!FileClip.isFolder(URL(fileURLWithPath: "/etc/hosts")))
    }

    @Test("missing files are found with one existence check per file, through the checker it is given")
    func missingChecksEachFileOnce() {
        let urls = ["/a", "/b", "/c"].map { URL(fileURLWithPath: $0) }
        var asked: [String] = []

        let missing = FileClip.missing(in: urls, exists: { path in
            asked.append(path)
            return path == "/b"
        })

        #expect(missing.map(\.path) == ["/a", "/c"])
        #expect(asked == ["/a", "/b", "/c"])
    }

    @Test("the off-main variant answers the same and does not need the main thread")
    func missingOffTheMainThread() async {
        let found = await FileClip.missing(inText: "file:///definitely/not/here.txt\nfile:///also/not/here")

        #expect(found.count == 2)
    }

    @Test("a single GIF file is an animated picture, whatever the case of its extension")
    func animatedPicture_isASingleGIFFile() {
        let gif = URL(fileURLWithPath: "/Users/me/Downloads/dance.GIF")

        #expect(FileClip.animatedPictureURL(inText: FileClip.encode([gif])) == gif)
        #expect(FileClip.animatedPictureURL(inText: FileClip.encode([a])) == nil)
        #expect(
            FileClip.animatedPictureURL(inText: FileClip.encode([gif, gif])) == nil,
            "several files are not one picture"
        )
        #expect(FileClip.animatedPictureURL(inText: "not a file") == nil)
    }

    @Test("Show in Finder selects only the files still on disk")
    func whenSomeFilesAreGone_thenOnlyTheOnesThatExistAreRevealable() {
        let text = FileClip.encode([a, b])
        #expect(FileClip.revealable(inText: text) { $0 == a } == [a])
        #expect(FileClip.revealable(inText: text) { _ in false }.isEmpty)
    }

    @Test("a clip is gone only when none of the files it names exist")
    func whenChecked_thenGoneOnlyIfEveryFileIsMissing() {
        let existing = [a]
        let exists: (String) -> Bool = { existing.map(\.path).contains($0) }
        #expect(FileClip.isGone([a, b], exists: exists) == false)
        #expect(FileClip.isGone([b], exists: exists))
        #expect(FileClip.isGone([], exists: exists) == false, "a clip that names no file is not a vanished one")
    }

    @Test("only the first few files are checked, so a huge drop costs a few stats")
    func whenManyFiles_thenCheckIsBounded() {
        let urls = (1...200).map { URL(fileURLWithPath: "/tmp/f\($0).txt") }
        var checked = 0
        _ = FileClip.isGone(urls, limit: 50) { _ in
            checked += 1
            return false
        }
        #expect(checked == 50)
    }
}
