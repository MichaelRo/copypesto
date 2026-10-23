// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("The watcher reads a board once and stops when it is too big")
struct PasteboardBoundedReadTests {
    private func watcher(on board: FakePasteboard) async -> (PasteboardWatcher, CaptureCollector) {
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari")
        )
        let collector = CaptureCollector()
        await watcher.onCapture { collector.append($0) }
        return (watcher, collector)
    }

    @Test("a plain text copy is read once, not once as bytes and again as a string")
    func whenPlainText_thenOneRead() async {
        let board = FakePasteboard()
        let (watcher, collector) = await watcher(on: board)

        board.write(types: [.string], data: [.string: Data("quarterly numbers".utf8)])
        await watcher.tick()

        #expect(collector.first?.payloadString == "quarterly numbers")
        #expect(board.contentReads == 1)
    }

    @Test("a text that is not UTF-8 bytes still arrives, through the string the system decodes")
    func whenBytesAreNotUTF8_thenTheSystemStringIsUsed() async {
        let board = FakePasteboard()
        let (watcher, collector) = await watcher(on: board)
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9])

        board.write(types: [.string], data: [.string: latin1], strings: [.string: "café"])
        await watcher.tick()

        #expect(collector.first?.payloadString == "café")
    }

    @Test("a text over the limit is read once, never decoded, and its rich flavours are never read")
    func whenTextIsTooLarge_thenNothingElseIsRead() async {
        let board = FakePasteboard()
        let (watcher, collector) = await watcher(on: board)
        let huge = Data(repeating: 0x61, count: ClipSizePolicy.maxTextBytes + 1)

        board.write(
            types: [.string, .html, .rtf],
            data: [.string: huge, .html: Data("<b>x</b>".utf8), .rtf: Data("{\\rtf1 x}".utf8)]
        )
        await watcher.tick()

        let capture = collector.first
        #expect(
            capture?.payload.count == huge.count,
            "the capture still reaches ingest, which refuses it with the message"
        )
        #expect(capture?.payloadString == nil)
        #expect(capture?.richPayload == nil)
        #expect(board.contentReads == 1)
    }
}
