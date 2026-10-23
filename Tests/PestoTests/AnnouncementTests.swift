// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

private final class Spoken: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func add(_ message: String) {
        lock.withLock { messages.append(message) }
    }

    var all: [String] {
        lock.withLock { messages }
    }
}

private final class PriorityLog: @unchecked Sendable {
    private let lock = NSLock()
    private var priorities: [Announcer.Priority] = []
    func add(_ priority: Announcer.Priority) {
        lock.withLock { priorities.append(priority) }
    }

    var all: [Announcer.Priority] {
        lock.withLock { priorities }
    }
}

extension HostedGlobals {
    /// Nothing transient was ever announced, so a VoiceOver user never learned that a paste needed ⌘V,
    /// that
    /// an error appeared, or that an AI answer or an Ask result had arrived.
    @Suite("Announcements for VoiceOver", .serialized)
    @MainActor
    struct AnnouncementTests {
        private func capturing(_ body: () async -> Void) async -> [String] {
            let spoken = Spoken()
            let original = Announcer.speak
            Announcer.speak = { message, _ in spoken.add(message) }
            defer { Announcer.speak = original }
            await body()
            return spoken.all
        }

        @Test("an error is spoken with high priority and a confirmation with the normal one")
        func whenAnnouncing_thenErrorsInterruptAndConfirmationsWait() {
            let priorities = PriorityLog()
            let original = Announcer.speak
            Announcer.speak = { _, priority in priorities.add(priority) }
            defer { Announcer.speak = original }

            AppState().showUserMessage("Couldn\u{2019}t save the shortcut")
            Announcer.announce("3 clips selected")

            #expect(priorities.all == [.high, .normal])
        }

        @Test("an error the user is shown is also spoken, with the same words")
        func whenErrorReported_thenSpoken() async {
            let state = AppState()

            let spoken = await capturing {
                state.attempt("Couldn\u{2019}t save the change") { throw CocoaError(.fileWriteUnknown) }
            }

            #expect(spoken == ["Couldn\u{2019}t save the change"])
        }

        @Test("applying an Ask result says which filters were set, or that nothing was understood")
        func whenAskApplied_thenFiltersAreSpoken() async {
            let state = AppState()

            let understood = await capturing {
                state.apply(AskPestoQuery(keywords: "invoice", types: [.url], range: .week))
            }
            let nothing = await capturing {
                state.apply(AskPestoQuery(keywords: "", types: [], range: .all))
            }

            #expect(understood == ["Filters applied: Links \u{00B7} past 7 days \u{00B7} \u{201C}invoice\u{201D}"])
            #expect(nothing == ["No filters found in that. Showing everything."])
        }

        @Test("the paste-needs-⌘V message is spoken by the toast")
        func whenManualPasteNeeded_thenSpoken() async {
            let spoken = await capturing { ToastAnnouncement.manualPaste() }

            #expect(spoken == ["Copied. Press \u{2318}V to paste."])
        }

        @Test("the stack HUD, which never takes focus, speaks its progress and its end")
        func whenStackAdvances_thenSpoken() async {
            let progress = await capturing {
                StackAnnouncement.progress(position: 2, count: 5, hint: "⌘V pastes the next")
            }
            let nextShortcut = await capturing { StackAnnouncement.progress(
                position: 1,
                count: 3,
                hint: "⇧⌘V to paste"
            ) }
            let done = await capturing { StackAnnouncement.complete() }

            #expect(progress == ["Paste One by One, clip 2 of 5. ⌘V pastes the next."])
            #expect(nextShortcut == ["Paste One by One, clip 1 of 3. ⇧⌘V to paste."])
            #expect(done == ["Paste One by One complete"])
        }

        @Test("an AI answer, and an AI failure, are both spoken")
        func whenAIResultArrives_thenSpoken() async {
            let ok = await capturing {
                AIResultAnnouncement.announce(AIResult(
                    action: .summarize,
                    sourcePreview: "x",
                    result: "Short summary."
                ))
            }
            let failed = await capturing {
                AIResultAnnouncement.announce(AIResult(
                    action: .summarize, sourcePreview: "x",
                    result: "Turn on Apple Intelligence in System Settings to use AI actions.", isError: true
                ))
            }

            #expect(ok == ["Summarize result: Short summary."])
            #expect(failed == ["Summarize failed. Turn on Apple Intelligence in System Settings to use AI actions."])
        }

        @Test("a count of selected clips reads correctly for one and for many")
        func whenSelectionChanges_thenCountIsSpoken() async {
            let one = await capturing { SelectionAnnouncement.announce(count: 1) }
            let many = await capturing { SelectionAnnouncement.announce(count: 3) }
            let none = await capturing { SelectionAnnouncement.announce(count: 0) }

            #expect(one == ["1 clip selected"])
            #expect(many == ["3 clips selected"])
            #expect(none == ["Selection cleared"])
        }

        @Test("opening the shelf says how many clips it holds, and says nothing about the history while it is locked")
        func whenShelfOpens_thenCountIsSpokenUnlessLocked() async {
            let many = await capturing { ShelfAnnouncement.opened(clipCount: 12, isLocked: false) }
            let one = await capturing { ShelfAnnouncement.opened(clipCount: 1, isLocked: false) }
            let none = await capturing { ShelfAnnouncement.opened(clipCount: 0, isLocked: false) }
            let locked = await capturing { ShelfAnnouncement.opened(clipCount: 12, isLocked: true) }

            #expect(many == ["Clipboard history, 12 clips"])
            #expect(one == ["Clipboard history, 1 clip"])
            #expect(none == ["Clipboard history, empty"])
            #expect(locked.isEmpty)
        }
    }
}
