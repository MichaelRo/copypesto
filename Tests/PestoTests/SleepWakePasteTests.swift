// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("SleepWakePaste", .serialized)
    @MainActor
    final class SleepWakePasteTests {
        @Test(
            "sleep, screen-sleep, wake, and screen-wake notifications interrupt an in-flight runPasteTask",
            arguments: [
                NSWorkspace.willSleepNotification,
                NSWorkspace.screensDidSleepNotification,
                NSWorkspace.didWakeNotification,
                NSWorkspace.screensDidWakeNotification
            ]
        )
        func whenSleepOrWakeNotification_thenRunPasteTaskAborts(notification: Notification.Name) async {
            let delegate = AppDelegate()
            delegate.installSleepWakeObservers()
            defer { delegate.removeSleepWakeObservers() }

            var cancelled = false
            delegate.runPasteTask(.overlaySelect(itemID: UUID())) { _ in
                do {
                    try await Task.sleep(for: .seconds(10))
                    return .writtenViaAccessibility
                } catch {
                    cancelled = true
                    return nil
                }
            }

            #expect(delegate.pasteTasks.isRunning)
            NSWorkspace.shared.notificationCenter.post(name: notification, object: nil)

            for _ in 0..<200 where delegate.pasteTasks.isRunning || !cancelled {
                try? await Task.sleep(for: .milliseconds(10))
            }

            #expect(!delegate.pasteTasks.isRunning)
            #expect(cancelled)
        }

        @Test("FillInPromptWindowController stays open until answered, and closes returning nil when interrupted")
        func whenFillInPromptInterruptedBySleep_thenClosesAndReturnsNil() async {
            let delegate = AppDelegate()
            delegate.installSleepWakeObservers()
            defer { delegate.removeSleepWakeObservers() }

            let field = SnippetField(label: "name", kind: .text(multiline: false), defaultValue: nil)
            var result: SnippetFills? = SnippetFills(values: ["name": "initial"])

            delegate.runPasteTask(.overlaySelect(itemID: UUID())) { host in
                result = await host.fillInPrompt.ask(title: "Greeting", fields: [field], initial: SnippetFills())
                return nil
            }

            for _ in 0..<200 where !delegate.fillInPrompt.isShowing {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(delegate.fillInPrompt.isShowing)

            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)

            for _ in 0..<200 where delegate.fillInPrompt.isShowing || delegate.pasteTasks.isRunning {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(!delegate.fillInPrompt.isShowing)
            #expect(result == nil)
        }
    }
}
