// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

struct FakeFrontmost: FrontmostAppProviding {
    let bundleID: String?
    var recent: [String] = []

    func frontmostBundleID() async -> String? {
        bundleID
    }

    func recentBundleIDs(within _: TimeInterval) async -> [String] {
        recent
    }
}

/// Thread-safe collector for captures emitted from the watcher (which runs on an actor).
final class CaptureCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var captures: [PasteboardCapture] = []

    func append(_ capture: PasteboardCapture) {
        lock.withLock { captures.append(capture) }
    }

    var all: [PasteboardCapture] {
        lock.withLock { captures }
    }

    var count: Int {
        lock.withLock { captures.count }
    }

    var isEmpty: Bool {
        lock.withLock { captures.isEmpty }
    }

    var first: PasteboardCapture? {
        lock.withLock { captures.first }
    }
}

struct RewritingFrontmost: FrontmostAppProviding {
    let onQuery: @Sendable () -> Void

    func frontmostBundleID() async -> String? {
        onQuery()
        return "com.apple.Safari"
    }
}

final class BlockCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var reasons: [ExclusionRules.BlockReason] = []
    func append(_ reason: ExclusionRules.BlockReason) {
        lock.withLock { reasons.append(reason) }
    }

    var all: [ExclusionRules.BlockReason] {
        lock.withLock { reasons }
    }
}

@Suite("PasteboardWatcher blocks are reported")
struct PasteboardWatcherBlockTests {
    @Test("a copy from a password manager is reported as blocked, with no capture")
    func whenExcludedApp_thenReported() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board, frontmostProvider: FakeFrontmost(bundleID: "com.1password.1password")
        )
        let captures = CaptureCollector()
        let blocks = BlockCollector()
        await watcher.onCapture { captures.append($0) }
        await watcher.onBlocked { blocks.append($0) }

        board.write(types: [.string], data: [.string: Data("secret".utf8)], strings: [.string: "secret"])
        await watcher.tick()

        #expect(captures.isEmpty)
        #expect(blocks.all == [.excludedApp])
    }

    @Test("a concealed copy is reported as blocked, and an ordinary copy is not")
    func whenConcealedMarker_thenReported() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: FakeFrontmost(bundleID: "com.example.x"))
        let blocks = BlockCollector()
        await watcher.onBlocked { blocks.append($0) }

        board.write(
            types: [.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")],
            data: [.string: Data("pw".utf8)], strings: [.string: "pw"]
        )
        await watcher.tick()
        board.write(types: [.string], data: [.string: Data("ok".utf8)], strings: [.string: "ok"])
        await watcher.tick()

        #expect(blocks.all == [.concealedMarker])
    }
}

@Suite("PasteboardWatcher")
struct PasteboardWatcherTests {
    @Test("rich text is captured as its plain string, not as raw RTF")
    func whenRichTextCopied_thenPlainStringIsCaptured() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari")
        )
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        board.write(
            types: [.rtf, .string],
            data: [.rtf: Data("{\\rtf1\\ansi hi}".utf8), .string: Data("hi".utf8)],
            strings: [.string: "hi"]
        )
        await watcher.tick()

        #expect(collector.first?.typeIdentifier == NSPasteboard.PasteboardType.string.rawValue)
        #expect(collector.first?.payloadString == "hi")
        #expect(collector.first?.payload == Data("hi".utf8))
        #expect(collector.first?.richPayload?.rtf == Data("{\\rtf1\\ansi hi}".utf8))
    }

    @Test("formatted text from Slack or Chrome (HTML + plain string) preserves HTML in richPayload")
    func whenHTMLAndPlainStringCopied_thenBothPlainAndHTMLAreCaptured() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.tinyspeck.slackmacgap")
        )
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }
        let html = "<b>bold</b> and <i>italic</i>"

        board.write(
            types: [.html, .string],
            data: [.html: Data(html.utf8), .string: Data("bold and italic".utf8)],
            strings: [.html: html, .string: "bold and italic"]
        )
        await watcher.tick()

        #expect(collector.first?.typeIdentifier == NSPasteboard.PasteboardType.string.rawValue)
        #expect(collector.first?.payloadString == "bold and italic")
        #expect(collector.first?.richPayload?.html == Data(html.utf8))
    }

    @Test("an oversized rich-text payload is not parsed, so a crafted board cannot stall or crash the parser")
    func whenRTFIsHuge_thenNotParsed() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari")
        )
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }
        let huge = Data("{\\rtf1\\ansi ".utf8) + Data(repeating: 0x61, count: 3_000_000) + Data("}".utf8)

        board.write(types: [.rtf], data: [.rtf: huge])
        await watcher.tick()

        #expect(collector.isEmpty)
    }

    @Test("rich text with no plain string is flattened from the RTF and keeps its RTF flavor")
    func whenOnlyRTF_thenFlattenedToPlainText() async throws {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari")
        )
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }
        let attributed = NSAttributedString(string: "flattened")
        let rtf = try #require(attributed.rtf(from: NSRange(location: 0, length: attributed.length)))

        board.write(types: [.rtf], data: [.rtf: rtf])
        await watcher.tick()

        #expect(collector.first?.typeIdentifier == NSPasteboard.PasteboardType.string.rawValue)
        #expect(collector.first?.payloadString == "flattened")
        #expect(collector.first?.richPayload?.rtf == rtf)
    }

    @Test("a WebP image or an HTML-only img tag from a browser is still captured as an image")
    func whenWebPOrHTMLOnlyImageCopied_thenCapturedAsImage() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.google.Chrome")
        )
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }
        let webpType = NSPasteboard.PasteboardType("org.webmproject.webp")
        let html = "<meta charset='utf-8'><img src=\"https://media.example.com/cats/dance.gif\"/>"

        board.write(
            types: [webpType, .html],
            data: [webpType: Data("RIFF....WEBPVP8 ".utf8), .html: Data(html.utf8)],
            strings: [.html: html]
        )
        await watcher.tick()

        #expect(collector.first?.typeIdentifier == "org.webmproject.webp")
        #expect(collector.first?.sourceImageURL?.absoluteString == "https://media.example.com/cats/dance.gif")

        // HTML-only fallback (when no bitmap flavor is readable):
        board.write(
            types: [.html],
            data: [.html: Data(html.utf8)],
            strings: [.html: html]
        )
        await watcher.tick()

        #expect(collector.count == 2)
        #expect(collector.all.last?.typeIdentifier == "com.compuserve.gif")
        #expect(collector.all.last?.sourceImageURL?.absoluteString == "https://media.example.com/cats/dance.gif")
    }

    @Test("a concealed write that lands while the watcher awaits is not ingested")
    func whenConcealedWriteDuringAwait_thenNothingCaptured() async {
        let board = FakePasteboard()
        let provider = RewritingFrontmost {
            board.write(
                types: [.init("org.nspasteboard.ConcealedType"), .string],
                data: [.string: Data("hunter2".utf8)],
                strings: [.string: "hunter2"]
            )
        }
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        board.write(types: [.string], data: [.string: Data("ordinary".utf8)], strings: [.string: "ordinary"])
        await watcher.tick()
        await watcher.tick()

        #expect(collector.isEmpty)
    }

    @Test("copying several files keeps all of them, in order, as one clip")
    func whenSeveralFilesCopied_thenAllAreCaptured() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.finder")
        )
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }
        let urls = [
            URL(fileURLWithPath: "/Users/me/basil.pdf"), URL(fileURLWithPath: "/Users/me/pine nuts.zip"),
            URL(fileURLWithPath: "/Users/me/parmesan.txt")
        ]

        board.writeFiles(urls)
        await watcher.tick()

        #expect(collector.count == 1)
        #expect(collector.first?.typeIdentifier == NSPasteboard.PasteboardType.fileURL.rawValue)
        #expect(FileClip.urls(from: collector.first?.payloadString ?? "") == urls)
        #expect(FileClip.urls(from: String(data: collector.first?.payload ?? Data(), encoding: .utf8) ?? "") == urls)
    }

    @Test("a single file is captured exactly as before")
    func whenOneFileCopied_thenPlainURL() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.finder")
        )
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }
        let url = URL(fileURLWithPath: "/Users/me/basil.pdf")

        board.writeFiles([url])
        await watcher.tick()

        #expect(collector.first?.payloadString == url.absoluteString)
    }

    @Test("tick captures a text payload from a safe source")
    func whenTextFromSafeSource_thenCaptureProduced() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        board.write(
            types: [.string],
            data: [.string: Data("hello".utf8)],
            strings: [.string: "hello"]
        )
        await watcher.tick()

        #expect(collector.count == 1)
        #expect(collector.first?.typeIdentifier == NSPasteboard.PasteboardType.string.rawValue)
        #expect(collector.first?.frontmostBundleID == "com.apple.Safari")
        #expect(collector.first?.payloadString == "hello")
    }

    @Test("tick drops payload when frontmost is excluded")
    func whenSourceIsExcluded_thenNoCapture() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.1password.1password")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        board.write(types: [.string], data: [.string: Data("secret".utf8)])
        await watcher.tick()
        #expect(collector.isEmpty)
    }

    @Test("tick drops payload when concealed marker is present")
    func whenConcealedMarker_thenNoCapture() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        board.write(
            types: [.init("org.nspasteboard.ConcealedType"), .string],
            data: [.string: Data("password123".utf8)]
        )
        await watcher.tick()
        #expect(collector.isEmpty)
    }

    @Test("tick is idempotent for unchanged changeCount")
    func whenSameChangeCount_thenNoNewCapture() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        board.write(types: [.string], data: [.string: Data("first".utf8)])
        await watcher.tick()
        await watcher.tick()
        await watcher.tick()
        #expect(collector.count == 1)
    }

    @Test("tick re-fires when changeCount advances")
    func whenNewChangeCount_thenNewCapture() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        board.write(types: [.string], data: [.string: Data("a".utf8)])
        await watcher.tick()
        board.write(types: [.string], data: [.string: Data("b".utf8)])
        await watcher.tick()
        #expect(collector.count == 2)
    }

    @Test("updateExclusionRules drops subsequent ticks from newly excluded source")
    func whenExclusionRulesUpdated_thenNewRuleApplied() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.example.vault")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        // Before exclusion: capture goes through.
        board.write(types: [.string], data: [.string: Data("before".utf8)])
        await watcher.tick()
        #expect(collector.count == 1)

        // Add runtime exclusion, then tick again.
        await watcher.updateExclusionRules(ExclusionRules(userAdditions: ["com.example.vault"]))
        board.write(types: [.string], data: [.string: Data("after".utf8)])
        await watcher.tick()

        #expect(collector.count == 1, "capture after updateExclusionRules must be dropped")
    }

    @Test("content hash is stable across identical payloads")
    func contentHashIsStable() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        board.write(types: [.string], data: [.string: Data("hello".utf8)])
        await watcher.tick()
        board.write(types: [.string], data: [.string: Data("hello".utf8)])
        await watcher.tick()

        let hashes = collector.all.map(\.contentHash)
        #expect(hashes.count == 2)
        #expect(hashes[0] == hashes[1])
    }

    @Test("whenPaused_thenTickDropsCaptures")
    func whenPaused_thenTickDropsCaptures() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        await watcher.pause()
        board.write(types: [.string], data: [.string: Data("secret".utf8)])
        await watcher.tick()

        #expect(collector.isEmpty, "captures must be suppressed while paused")
        #expect(await watcher.isPaused == true)
    }

    @Test("whenResumedAfterPause_thenNewCapturesAreDelivered")
    func whenResumedAfterPause_thenNewCapturesAreDelivered() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        // Pause, write while paused, resume, then write again.
        await watcher.pause()
        board.write(types: [.string], data: [.string: Data("paused-content".utf8)])
        await watcher.tick()
        #expect(collector.isEmpty)

        await watcher.resume()
        board.write(
            types: [.string],
            data: [.string: Data("resumed-content".utf8)],
            strings: [.string: "resumed-content"]
        )
        await watcher.tick()

        #expect(collector.count == 1)
        #expect(collector.first?.payloadString == "resumed-content")
        #expect(await watcher.isPaused == false)
    }

    @Test("pauseUpdatesLastChangeCount_soResumeDoesNotReplayMissedEvents")
    func pauseUpdatesLastChangeCount_soResumeDoesNotReplayMissedEvents() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari")
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { capture in collector.append(capture) }

        // Write something before pause so lastChangeCount is non-zero.
        board.write(types: [.string], data: [.string: Data("first".utf8)])
        await watcher.tick()
        #expect(collector.count == 1)

        // Pause and write — lastChangeCount syncs with current changeCount inside pause().
        await watcher.pause()
        board.write(types: [.string], data: [.string: Data("during-pause".utf8)])

        // Resume and tick without a new write — should not replay the paused event.
        await watcher.resume()
        await watcher.tick()

        #expect(collector.count == 1, "paused event must not be replayed on resume")
    }
}

@Suite("PasteboardWatcher own writes")
struct PasteboardWatcherOwnWriteTests {
    private func write(_ board: FakePasteboard, _ text: String) {
        board.write(types: [.string], data: [.string: Data(text.utf8)], strings: [.string: text])
    }

    private func makeWatcher(
        _ board: FakePasteboard,
        _ gate: OwnWriteGate
    ) async
    -> (PasteboardWatcher, CaptureCollector) {
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari"),
            ownWrites: gate
        )
        let collector = CaptureCollector()
        await watcher.onCapture { collector.append($0) }
        return (watcher, collector)
    }

    @Test("a write made through the gate is not captured")
    func whenOwnWrite_thenNotCaptured() async {
        let board = FakePasteboard()
        let gate = OwnWriteGate()
        let (watcher, collector) = await makeWatcher(board, gate)

        gate.write(to: board) { write($0, "pasted") }
        await watcher.tick()

        #expect(collector.isEmpty)
    }

    @Test("a real copy after an own write is still captured")
    func whenRealCopyFollowsOwnWrite_thenCaptured() async {
        let board = FakePasteboard()
        let gate = OwnWriteGate()
        let (watcher, collector) = await makeWatcher(board, gate)

        gate.write(to: board) { write($0, "pasted") }
        await watcher.tick()
        write(board, "real copy")
        await watcher.tick()

        #expect(collector.count == 1)
        #expect(collector.first?.payloadString == "real copy")
    }

    @Test("an own write that changes the pasteboard twice does not swallow the next copy")
    func whenOwnWriteBumpsChangeCountTwice_thenNextRealCopyCaptured() async {
        let board = FakePasteboard()
        let gate = OwnWriteGate()
        let (watcher, collector) = await makeWatcher(board, gate)

        gate.write(to: board) {
            write($0, "template")
            write($0, "template filled")
        }
        await watcher.tick()
        write(board, "real copy")
        await watcher.tick()

        #expect(collector.count == 1)
        #expect(collector.first?.payloadString == "real copy")
    }

    @Test("an own write nobody polled before the next copy does not hide that copy")
    func whenOwnWriteUnpolledThenRealCopy_thenRealCopyCaptured() async {
        let board = FakePasteboard()
        let gate = OwnWriteGate()
        let (watcher, collector) = await makeWatcher(board, gate)
        gate.write(to: board) { write($0, "pasted") }
        write(board, "real copy")
        await watcher.tick()
        #expect(collector.count == 1)
    }

    @Test("a tick during an open write is deferred, then the finished write is ignored")
    func whenTickDuringOwnWrite_thenDeferredAndIgnored() async {
        let board = FakePasteboard()
        let gate = OwnWriteGate()
        let (watcher, collector) = await makeWatcher(board, gate)
        gate.write(to: board) { board in
            write(board, "partial")
            let ticked = DispatchSemaphore(value: 0)
            Task.detached { await watcher.tick()
                ticked.signal()
            }
            ticked.wait()
        }
        await watcher.tick()
        #expect(collector.isEmpty)
    }
}

@Suite("PasteboardWatcher recent sources")
struct PasteboardWatcherRecentSourceTests {
    @Test("a copy made in a password manager that lost focus before the poll is still dropped")
    func whenExcludedAppWasFrontmostJustBefore_thenDropped() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari", recent: ["com.1password.1password"])
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { collector.append($0) }
        board.write(types: [.string], data: [.string: Data("hunter2".utf8)], strings: [.string: "hunter2"])
        await watcher.tick()
        #expect(collector.isEmpty)
    }

    @Test("recent non-excluded apps do not block capture")
    func whenRecentAppsAreNotExcluded_thenCaptured() async {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.apple.Safari", recent: ["com.apple.TextEdit"])
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: provider)
        let collector = CaptureCollector()
        await watcher.onCapture { collector.append($0) }
        board.write(types: [.string], data: [.string: Data("hi".utf8)], strings: [.string: "hi"])
        await watcher.tick()
        #expect(collector.count == 1)
    }
}
