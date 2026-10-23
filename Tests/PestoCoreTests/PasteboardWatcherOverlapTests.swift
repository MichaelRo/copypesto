// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

final class ConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var highest = 0

    func enter() {
        lock.withLock {
            running += 1
            highest = max(highest, running)
        }
    }

    func leave() {
        lock.withLock { running -= 1 }
    }

    var mostAtOnce: Int {
        lock.withLock { highest }
    }
}

@Suite("PasteboardWatcher ticks do not overlap")
struct PasteboardWatcherOverlapTests {
    private func write(_ text: String, to board: FakePasteboard) {
        board.write(types: [.string], data: [.string: Data(text.utf8)], strings: [.string: text])
    }

    @Test("a tick that fires while the previous copy is still being handled waits for a later tick")
    func whenTheHandlerIsSlow_thenCopiesAreHandledOneAtATimeAndInOrder() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: FakeFrontmost(bundleID: "com.example.x"))
        let probe = ConcurrencyProbe()
        let handled = CaptureCollector()
        await watcher.onCapture { capture in
            probe.enter()
            try? await Task.sleep(for: .milliseconds(150))
            handled.append(capture)
            probe.leave()
        }

        write("first", to: board)
        async let firstTick: Void = watcher.tick()
        try? await Task.sleep(for: .milliseconds(40))
        write("second", to: board)
        async let secondTick: Void = watcher.tick()
        _ = await (firstTick, secondTick)
        await watcher.tick()

        #expect(probe.mostAtOnce == 1, "two copies were being handled at once")
        #expect(handled.all.compactMap(\.payloadString) == ["first", "second"])
    }
}
