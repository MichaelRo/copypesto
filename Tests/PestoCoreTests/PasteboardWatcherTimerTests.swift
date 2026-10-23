// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("The watcher's timer does no work while the clipboard has not changed (P-05)")
struct PasteboardWatcherTimerTests {
    @Test("an idle board starts no tick, and a copy still arrives")
    func whenNothingIsCopied_thenNoTickStarts() async throws {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari")
        )
        let collector = CaptureCollector()
        await watcher.onCapture { collector.append($0) }
        await watcher.start(period: .milliseconds(20))
        defer { Task { await watcher.stop() } }

        try await Task.sleep(for: .milliseconds(400))
        #expect(await watcher.ticksStarted == 0, "the timer started a tick for a board that had not changed")

        board.write(types: [.string], data: [.string: Data("quarterly numbers".utf8)])
        for _ in 0..<100 where collector.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(collector.first?.payloadString == "quarterly numbers")
        #expect(await watcher.ticksStarted >= 1)
    }
}
