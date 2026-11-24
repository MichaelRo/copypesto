// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore
import UIKit

/// The "Add Clipboard to Pesto" action (Action Button, Back Tap, a Shortcuts automation): the current clipboard goes
/// through the normal capture path and ingest, as the Paste button's does. It runs with Pesto in front, because iOS
/// lets only an app on screen read what another app copied, and it shows iOS's own paste prompt unless the person
/// allowed pasting from other apps in Pesto's settings.
extension MobileAppState {
    private static let addClipboardLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "AddClipboard")

    func addClipboardFromShortcut(
        pasteboard: UIPasteboard = AppPasteboard.general, defaults: UserDefaults = AppDefaults.store
    ) async throws {
        boot()
        guard let service = storageService else { throw ShortcutFailure.notReady }
        guard !isHistoryLockedNow() else { throw ShortcutFailure.locked }
        guard pasteboard.hasStrings || pasteboard.hasURLs || pasteboard.hasImages else {
            throw ShortcutFailure.emptyClipboard
        }
        let count = pasteboard.changeCount
        let capture: PasteboardCapture?
        do {
            capture = try await ItemProviderCapture.capture(
                from: pasteboard.itemProviders, pasteboardTypes: pasteboard.types
            )
        } catch {
            Self.addClipboardLogger
                .error("Reading the clipboard failed: \(error.localizedDescription, privacy: .public)")
            throw ShortcutFailure.failed
        }
        guard let capture else { throw ShortcutFailure.emptyClipboard }
        do {
            try await service.ingest(
                capture.with(captureMethod: .shortcut),
                collectionID: resolvedDefaultPasteCollectionID(defaults: defaults),
                assignCollectionOnlyIfUnfiled: true
            )
        } catch let refusal as ClipSizePolicy.TooLarge {
            throw ShortcutFailure.refused(refusal.message)
        } catch {
            Self.addClipboardLogger
                .error("Adding the clipboard failed: \(error.localizedDescription, privacy: .public)")
            throw ShortcutFailure.failed
        }
        defaults.set(count, for: Setting.lastSeenPasteboardChange)
        clipboardOfferCount = nil
    }
}

extension MobileAppState {
    func addClipboardFromShortcut() async throws {
        try await addClipboardFromShortcut(pasteboard: AppPasteboard.general, defaults: AppDefaults.store)
    }
}
