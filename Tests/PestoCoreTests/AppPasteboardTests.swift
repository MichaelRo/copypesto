// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("AppPasteboard isolation")
struct AppPasteboardTests {
    private func configuration(mode: LaunchMode, session: String = "tests-pasteboard") -> RuntimeConfiguration {
        RuntimeConfiguration(mode: mode, session: session, seed: .basic, accessibility: .trusted)
    }

    @Test("a normal launch uses the system clipboard")
    func whenNormal_thenGeneralPasteboard() {
        let board = AppPasteboard.make(for: configuration(mode: .normal))
        #expect(board.name == NSPasteboard.general.name)
    }

    @Test("a uiTest launch uses a private named pasteboard scoped to the session")
    func whenUITest_thenNamedSessionPasteboard() {
        let config = configuration(mode: .uiTest, session: "tests-pasteboard-name")
        let board = AppPasteboard.make(for: config)
        #expect(board.name.rawValue == "io.pesto.uitest.tests-pasteboard-name")
        #expect(board.name != NSPasteboard.general.name)
    }

    @Test("a hosted test run never shares the system clipboard")
    func whenHostedTests_thenNotGeneralPasteboard() {
        let board = AppPasteboard.make(for: configuration(mode: .hostedTests))
        #expect(board.name != NSPasteboard.general.name)
    }

    @Test("writes to the private pasteboard never reach the system clipboard")
    func whenWritingToPrivateBoard_thenGeneralUnchanged() {
        let board = AppPasteboard.make(for: configuration(mode: .uiTest, session: "tests-pasteboard-write"))
        let sentinel = "pesto-isolation-\(UUID().uuidString)"
        board.clearContents()
        defer { board.clearContents() }

        board.setString(sentinel, forType: .string)

        #expect(board.string(forType: .string) == sentinel)
        #expect(NSPasteboard.general.string(forType: .string) != sentinel)
    }

    @Test("another process can reach the same private pasteboard by name")
    func whenLookedUpByName_thenSameBoard() {
        let config = configuration(mode: .uiTest, session: "tests-pasteboard-shared")
        let appSide = AppPasteboard.make(for: config)
        let runnerSide = NSPasteboard(name: NSPasteboard.Name(config.pasteboardName))
        let sentinel = "pesto-shared-\(UUID().uuidString)"
        runnerSide.clearContents()
        defer { runnerSide.clearContents() }

        runnerSide.setString(sentinel, forType: .string)

        #expect(appSide.string(forType: .string) == sentinel)
    }

    @Test("a uiTest launch asked for the real clipboard uses it, and only then")
    func whenUITestAsksForRealPaste_thenGeneralPasteboard() {
        var config = configuration(mode: .uiTest, session: "tests-pasteboard-real")
        #expect(AppPasteboard.make(for: config).name != NSPasteboard.general.name)
        config.usesRealPasteboard = true
        #expect(AppPasteboard.make(for: config).name == NSPasteboard.general.name)
    }

    @Test("a hosted test run never gets the real clipboard, even if asked")
    func whenHostedTestsAskForRealPaste_thenStillPrivate() {
        var config = configuration(mode: .hostedTests)
        config.usesRealPasteboard = true
        #expect(AppPasteboard.make(for: config).name != NSPasteboard.general.name)
    }
}
