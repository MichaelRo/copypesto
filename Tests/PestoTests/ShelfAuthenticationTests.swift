// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import PestoCore
import Synchronization
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Authenticating without leaving the shelf", .serialized)
    @MainActor
    final class ShelfAuthenticationTests {
        private let granted = StubUserAuthenticator(available: true, grants: true)
        private let refused = StubUserAuthenticator(available: true, grants: false)
        private let unavailable = StubUserAuthenticator(available: false, grants: false)

        private func shelfState() -> AppState {
            let state = AppState()
            state.isOverlayVisible = true
            return state
        }

        /// Waits, bounded, for the shelf to be showing its prompt.
        private func waitForPrompt(_ state: AppState) async {
            for _ in 0..<2000 where state.shelfAuthentication == nil {
                await Task.yield()
            }
        }

        @Test("a recent authentication is enough: nothing is shown and nothing is asked")
        func whenWithinTheWindow_thenNoPrompt() async {
            let state = AppState()
            let grace = AuthenticationGrace()
            grace.record()

            let allowed = await state.authenticateInShelf(
                reason: "x", authenticator: refused, embeddedAvailable: true, grace: grace
            )

            #expect(allowed)
            #expect(state.shelfAuthentication == nil)
        }

        @Test("with the embedded prompt available the shelf shows it and waits for the answer")
        func whenEmbeddedAvailable_thenThePromptIsShownInTheShelf() async {
            let state = shelfState()
            let grace = AuthenticationGrace()
            let outcome = Task {
                await state.authenticateInShelf(
                    reason: "Show a clip",
                    authenticator: refused,
                    embeddedAvailable: true,
                    grace: grace
                )
            }
            while state.shelfAuthentication == nil {
                await Task.yield()
            }

            #expect(state.shelfAuthentication?.reason == "Show a clip")
            state.finishShelfAuthentication(success: true, grace: grace)

            #expect(await outcome.value)
            #expect(state.shelfAuthentication == nil)
            #expect(grace.isActive(window: 300), "a success starts the window")
        }

        @Test("cancelling the prompt refuses and starts no window")
        func whenCancelled_thenRefused() async {
            let state = shelfState()
            let grace = AuthenticationGrace()
            let outcome = Task {
                await state.authenticateInShelf(
                    reason: "x",
                    authenticator: granted,
                    embeddedAvailable: true,
                    grace: grace
                )
            }
            while state.shelfAuthentication == nil {
                await Task.yield()
            }

            state.finishShelfAuthentication(success: false, grace: grace)

            #expect(await !outcome.value)
            #expect(!grace.isActive(window: 300))
        }

        @Test("without the embedded prompt the system authenticator is used")
        func whenEmbeddedUnavailable_thenSystemAuthenticator() async {
            let state = AppState()
            let allowed = await state.authenticateInShelf(
                reason: "x", authenticator: granted, embeddedAvailable: false, grace: AuthenticationGrace()
            )
            let denied = await state.authenticateInShelf(
                reason: "x", authenticator: refused, embeddedAvailable: false, grace: AuthenticationGrace()
            )

            #expect(allowed)
            #expect(!denied)
            #expect(state.shelfAuthentication == nil)
        }

        @Test("a Mac that cannot authenticate at all cannot show a hidden clip: it fails closed")
        func whenNothingCanAuthenticate_thenRefused() async {
            let allowed = await AppState().authenticateInShelf(
                reason: "x", authenticator: unavailable, embeddedAvailable: false, grace: AuthenticationGrace()
            )
            #expect(!allowed)
        }

        @Test("a second request while one is open is refused instead of replacing it")
        func whenAlreadyAsking_thenTheSecondIsRefused() async {
            let state = shelfState()
            let grace = AuthenticationGrace()
            let first = Task {
                await state.authenticateInShelf(
                    reason: "first",
                    authenticator: granted,
                    embeddedAvailable: true,
                    grace: grace
                )
            }
            while state.shelfAuthentication == nil {
                await Task.yield()
            }

            let second = await state.authenticateInShelf(
                reason: "second", authenticator: granted, embeddedAvailable: true, grace: grace
            )
            state.finishShelfAuthentication(success: true, grace: grace)

            #expect(!second)
            #expect(await first.value)
        }

        @Test("a success that arrives after the prompt is gone (the shelf closed on a system dialog) still counts")
        func whenSuccessArrivesLate_thenTheWindowStillOpens() {
            let state = shelfState()
            let grace = AuthenticationGrace()

            state.finishShelfAuthentication(success: true, grace: grace)

            #expect(grace.isActive())
        }

        @Test("the shelf is held open while the system password dialog is up, and gets its keys back after")
        func whenAPasswordDialogIsUp_thenTheShelfIsHeldOpen() async {
            let state = shelfState()
            var restored = 0
            state.onRestoreKeyFocus = { restored += 1 }
            #expect(!state.keepsShelfOpenForAuthentication)

            var heldDuring = false
            _ = await state.withSystemAuthenticationDialog {
                heldDuring = state.keepsShelfOpenForAuthentication
                return true
            }

            #expect(heldDuring)
            #expect(!state.keepsShelfOpenForAuthentication)
            #expect(restored == 1)
        }

        @Test("another app activating while the shelf is authenticating does not dismiss the shelf")
        func whenOtherAppActivatesDuringAuthentication_thenShelfStaysOpen() {
            let delegate = AppDelegate()
            delegate.appState.isOverlayVisible = true
            delegate.appState.systemAuthenticationDialogs = 1

            delegate.dismissShelfOnExternalAppActivationIfNeeded()

            #expect(delegate.appState.isOverlayVisible)

            delegate.appState.systemAuthenticationDialogs = 0
            delegate.dismissShelfOnExternalAppActivationIfNeeded()

            #expect(!delegate.appState.isOverlayVisible)
        }

        @Test("History Lock unlock shares grace timer with Show Hidden Clip and expires after the window")
        func whenHistoryLockUnlocked_thenShowHiddenClipSharesGraceUntilExpiry() async {
            let savedMinutes = AppDefaults.store.value(for: Setting.authenticationGraceMinutes)
            AppDefaults.store.set(1, for: Setting.authenticationGraceMinutes)
            defer { AppDefaults.store.set(savedMinutes, for: Setting.authenticationGraceMinutes) }

            let clock = Mutex(Date(timeIntervalSince1970: 1000))
            let grace = AuthenticationGrace { clock.withLock { $0 } }
            let state = shelfState()

            #expect(await HistoryLockPolicy.unlock(using: granted, grace: grace))
            #expect(grace.isActive(window: 60))

            // Within grace window: Show Hidden Clip does not re-prompt even with a refusing authenticator.
            let allowedWhileWarm = await state.authenticateInShelf(
                reason: "Show hidden clip", authenticator: refused, embeddedAvailable: false, grace: grace
            )
            #expect(allowedWhileWarm)

            // Advance past the 60s window: Show Hidden Clip must re-authenticate.
            clock.withLock { $0 = $0.addingTimeInterval(61) }
            #expect(!grace.isActive(window: 60))
            let deniedAfterExpiry = await state.authenticateInShelf(
                reason: "Show hidden clip", authenticator: refused, embeddedAvailable: false, grace: grace
            )
            #expect(!deniedAfterExpiry)
        }

        @Test("willSleepNotification clears AuthenticationGrace.shared")
        func whenWillSleepNotification_thenClearsSharedGrace() async {
            let delegate = AppDelegate()
            delegate.installSleepWakeObservers()
            defer { delegate.removeSleepWakeObservers() }

            AuthenticationGrace.shared.record()
            #expect(AuthenticationGrace.shared.isActive(window: 300))

            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            await Task.yield()

            #expect(!AuthenticationGrace.shared.isActive(window: 300))
        }

        @Test("OverlayWindowController keeps shelf open on resignKey when keepsShelfOpenForAuthentication is true")
        func whenExternalWindowActivatesDuringAuth_thenOverlayStaysOpen() {
            NSApp.activate(ignoringOtherApps: true)
            let state = shelfState()
            let controller = OverlayWindowController(appState: state)
            var dismissed = 0
            controller.onClickOutside = { dismissed += 1 }
            controller.show()
            defer { controller.hide() }

            let external = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            external.isReleasedWhenClosed = false
            defer { external.orderOut(nil) }

            state.systemAuthenticationDialogs = 1
            external.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: controller.overlayWindow)
            #expect(dismissed == 0)

            state.systemAuthenticationDialogs = 0
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: controller.overlayWindow)
            #expect(dismissed == 1)
        }
    }
}
