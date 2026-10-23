// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("PasteboardWatcher allowed concealed copies")
struct PasteboardWatcherAllowedConcealedTests {
    private func run(allowed: Bool) async -> [PasteboardCapture] {
        let board = FakePasteboard()
        let provider = FakeFrontmost(bundleID: "com.1password.1password")
        let allowances = allowed ? ["com.1password.1password": Date().addingTimeInterval(600)] : [:]
        let watcher = PasteboardWatcher(
            pasteboard: board, frontmostProvider: provider,
            exclusionRules: ExclusionRules(temporaryAllowances: allowances)
        )
        let collector = CaptureCollector()
        await watcher.onCapture { collector.append($0) }
        board.write(
            types: [.init("org.nspasteboard.ConcealedType"), .string],
            data: [.string: Data("hunter2".utf8)], strings: [.string: "hunter2"]
        )
        await watcher.tick()
        return collector.all
    }

    @Test("an allowed app's concealed copy is captured and marked concealed")
    func whenAllowed_thenCapturedAndFlagged() async {
        let captures = await run(allowed: true)
        #expect(captures.count == 1)
        #expect(captures.first?.isConcealed == true)
    }

    @Test("without an allowance it is dropped")
    func whenNotAllowed_thenDropped() async {
        #expect(await run(allowed: false).isEmpty)
    }
}
