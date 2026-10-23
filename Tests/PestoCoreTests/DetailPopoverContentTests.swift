// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("What the hover popover shows")
struct DetailPopoverContentTests {
    @Test("each kind of clip has something of its own to show")
    func whenNotASecret_thenEachTypeHasABody() {
        func body(_ type: ClipboardType, _ text: String = "plain words") -> DetailPopoverContent.Body {
            DetailPopoverContent.body(type: type, isSensitive: false, text: text)
        }

        #expect(body(.text) == .text)
        #expect(body(.text, "# Title\n- one") == .markdown)
        #expect(body(.code) == .code)
        #expect(body(.url) == .link)
        #expect(body(.image) == .picture)
        #expect(body(.file) == .files)
        #expect(body(.color) == .color)
    }

    @Test("markdown elements are classified as markdown and render into attributed strings")
    func whenMarkdownElementsPresent_thenClassifiedAsMarkdownAndRenders() {
        let samples = [
            "# Heading 1\nSome paragraph",
            "## Heading 2\nSubtitle",
            "This is **bold text** in paragraph",
            "- Item 1\n- Item 2\n- Item 3",
            "```swift\nlet x = 10\n```",
            "Check [Pesto](https://copypesto.net) link",
            "This is _italicized text_"
        ]

        for sample in samples {
            #expect(DetailPopoverContent.looksLikeMarkdown(sample))
            #expect(DetailPopoverContent.body(type: .text, isSensitive: false, text: sample) == .markdown)
            let attributed = try? AttributedString(
                markdown: sample,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            #expect(attributed != nil)
            #expect(!(attributed?.characters.isEmpty ?? true))
        }

        #expect(!DetailPopoverContent.looksLikeMarkdown("Simple plain text without formatting"))
    }

    @Test("a secret shows only what is known about it, never its text")
    func whenSecret_thenMetadataOnly() {
        for type in ClipboardType.allCases {
            #expect(DetailPopoverContent.body(type: type, isSensitive: true, text: "sk-live-123") == .metadataOnly)
        }
    }

    @Test("when a sensitive clip is revealed, the popover shows its content instead of metadataOnly")
    func whenSensitiveClipRevealed_thenBodyShowsContent() {
        #expect(DetailPopoverContent.body(type: .text, isSensitive: false, text: "unmasked password") == .text)
        #expect(DetailPopoverContent.body(type: .text, isSensitive: false, text: "# Header\n- list item") == .markdown)
        #expect(DetailPopoverContent.body(type: .code, isSensitive: false, text: "let key = 123") == .code)
    }

    @Test("long text is cut for the popover, and says it was cut")
    func shown_cutsLongText() {
        let long = String(repeating: "a", count: DetailPopoverContent.maxCharacters + 50)

        let cut = DetailPopoverContent.shown(long)
        let whole = DetailPopoverContent.shown("short")

        #expect(cut.text.count == DetailPopoverContent.maxCharacters)
        #expect(cut.wasCut)
        #expect(whole.text == "short")
        #expect(!whole.wasCut)
    }

    @Test("a clip too big to read on the main thread is not decrypted for a popover")
    func canRead_refusesHugeClips() {
        #expect(DetailPopoverContent.canRead(byteSize: 10_000))
        #expect(!DetailPopoverContent.canRead(byteSize: DetailPopoverContent.maxReadableBytes + 1))
    }

    private func facts(
        _ type: ClipboardType, secret: String? = nil, remote: Bool = false, characters: Int = 0, text: String = "",
        cut: Bool = false, language: String? = nil, bytes: Int = 0, files: Int = 0,
        rgb: DetailPopoverContent.RGB? = nil, collection: String? = nil
    )
    -> [DetailFact] {
        DetailPopoverContent.facts(.init(
            type: type, secretKind: secret, isRemote: remote, copiedAt: Date(timeIntervalSince1970: 0),
            byteSize: bytes, characterCount: characters, shownText: text, wasCut: cut, language: language,
            fileCount: files, rgb: rgb, collectionName: collection
        ))
    }

    private let copied = DetailFact.copied(Date(timeIntervalSince1970: 0))

    @Test("text says when it was copied and how long it is")
    func facts_text() {
        #expect(facts(.text, characters: 98, text: "short") == [copied, .characters(98)])
    }

    @Test("a clip captured before the length was stored falls back to the text on hand")
    func facts_textWithoutStoredLength() {
        #expect(facts(.text, text: "twelve chars") == [copied, .characters(12)])
    }

    @Test("a text clip that was cut says how much of it is shown")
    func facts_cutText() {
        #expect(facts(.text, characters: 12_480, text: "x", cut: true) ==
            [copied, .charactersShown(shown: DetailPopoverContent.maxCharacters, total: 12_480)])
    }

    @Test("code names its language and counts its lines, ignoring one trailing line break")
    func facts_code() {
        #expect(facts(.code, text: "a\nb\nc\n", language: "Python") == [copied, .language("Python"), .lines(3)])
        #expect(facts(.code, text: "one line") == [copied, .lines(1)])
    }

    @Test("a link adds nothing the address above does not already say")
    func facts_link() {
        #expect(facts(.url, bytes: 41) == [copied])
    }

    @Test("a picture and a set of files say their size, and the files their count")
    func facts_pictureAndFiles() {
        #expect(facts(.image, bytes: 18_432) == [copied, .bytes(18_432)])
        #expect(facts(.file, bytes: 4_200_000, files: 5) == [copied, .files(5), .bytes(4_200_000)])
    }

    @Test("a picture with pixel dimensions shows width, height and bytes")
    func facts_pictureWithDimensions() {
        let input = DetailPopoverContent.FactsInput(
            type: .image, secretKind: nil, isRemote: false, copiedAt: Date(timeIntervalSince1970: 0),
            byteSize: 100_000, characterCount: 0, shownText: "", wasCut: false, language: nil,
            fileCount: 0, rgb: nil, collectionName: nil, pixelWidth: 1920, pixelHeight: 1080, pasteCount: 4
        )
        #expect(DetailPopoverContent.facts(input) == [
            copied, .dimensions(width: 1920, height: 1080), .bytes(100_000), .pasteCount(4)
        ])
    }

    @Test("a colour says its red, green and blue")
    func facts_color() {
        #expect(facts(.color, rgb: .init(red: 82, green: 157, blue: 110)) == [
            copied,
            .rgb(red: 82, green: 157, blue: 110)
        ])
        #expect(facts(.color) == [copied])
    }

    @Test("a secret says its kind and nothing about its text")
    func facts_secret() {
        #expect(facts(.text, secret: "API key", characters: 40, text: "sk-live-123") == [
            copied,
            .secretKind("API key")
        ])
    }

    @Test("a clip from another device is named as such, and a collection comes last")
    func facts_remoteAndCollection() {
        #expect(facts(.text, remote: true, characters: 44, collection: "Recipes") ==
            [.fromPhone, copied, .characters(44), .collection("Recipes")])
    }

    @Test("an empty collection name is not shown")
    func facts_emptyCollectionName() {
        #expect(facts(.text, characters: 1, collection: "") == [copied, .characters(1)])
    }
}
