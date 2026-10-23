// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

private final class CountingBoard: PasteboardReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0

    var changeCount: Int {
        lock.withLock {
            reads += 1
            return 1
        }
    }

    var readCount: Int {
        lock.withLock { reads }
    }

    func types() -> [NSPasteboard.PasteboardType] {
        []
    }

    func data(forType _: NSPasteboard.PasteboardType) -> Data? {
        nil
    }

    func string(forType _: NSPasteboard.PasteboardType) -> String? {
        nil
    }

    func fileURLs() -> [URL] {
        []
    }
}

private final class MutableIdle: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds = 0.0

    var value: Double {
        get { lock.withLock { seconds } }
        set { lock.withLock { seconds = newValue } }
    }
}

@Suite("How often the watcher looks")
struct PollPolicyTests {
    @Test("it looks often just after the person used the keyboard or mouse, when a copy is likely")
    func whenJustUsed_thenFast() {
        #expect(PollPolicy.period(secondsSinceInput: 0) == .milliseconds(60))
        #expect(PollPolicy.period(secondsSinceInput: 2.9) == .milliseconds(60))
    }

    @Test("it relaxes to the usual 200 ms while the person is around, and further when they are away")
    func whenQuiet_thenSlower() {
        #expect(PollPolicy.period(secondsSinceInput: 3) == .milliseconds(200))
        #expect(PollPolicy.period(secondsSinceInput: 29) == .milliseconds(200))
        #expect(PollPolicy.period(secondsSinceInput: 30) == .milliseconds(500))
        #expect(PollPolicy.period(secondsSinceInput: 3600) == .milliseconds(500))
    }

    @Test("an adaptive watcher looks far more often after input than after a long quiet")
    func whenAdaptive_thenCadenceFollowsInput() async throws {
        let board = CountingBoard()
        let idle = MutableIdle()
        let watcher = PasteboardWatcher(pasteboard: board, inputIdleSeconds: { idle.value })
        idle.value = 0
        await watcher.start(adaptive: true)
        try await Task.sleep(for: .milliseconds(150))
        let before = board.readCount
        try await Task.sleep(for: .seconds(1))
        let afterInput = board.readCount - before

        idle.value = 600
        try await Task.sleep(for: .milliseconds(700))
        let quietStart = board.readCount
        try await Task.sleep(for: .seconds(1))
        let afterQuiet = board.readCount - quietStart
        await watcher.stop()

        #expect(afterInput >= 3 * afterQuiet, "after input \(afterInput) looks, after a quiet \(afterQuiet)")
        #expect(afterQuiet <= 6)
    }

    @Test("a watcher that is not adaptive keeps its period whatever the input")
    func whenNotAdaptive_thenFixed() async throws {
        let board = CountingBoard()
        let watcher = PasteboardWatcher(pasteboard: board, inputIdleSeconds: { 0 })
        await watcher.start()
        try await Task.sleep(for: .milliseconds(300))
        let start = board.readCount
        try await Task.sleep(for: .seconds(1))
        let reads = board.readCount - start
        await watcher.stop()

        #expect((3...8).contains(reads), "a 200 ms period read the board \(reads) times in a second")
    }
}
