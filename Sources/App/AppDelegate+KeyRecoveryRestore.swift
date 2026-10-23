// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI

/// Reports the closing of the recovery window by any route, the title bar's close button included.
final class KeyRecoveryWindowCloser: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_: Notification) {
        let finish = onClose
        onClose = nil
        finish?()
    }
}

extension AppDelegate {
    /// The restore sheet in a window of its own, shown from the "can't unlock your history" alert. `finished` gets true
    /// when the unreadable history was replaced by the backup. Closing the window before the backup is restored changes
    /// nothing and gets false, so the alert comes back.
    func showKeyRecoveryRestore(container: ModelContainer, context: ModelContext, finished: @escaping (Bool) -> Void) {
        var replaced = false
        let closer = KeyRecoveryWindowCloser()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = String(localized: "Restore from Backup")
        window.delegate = closer
        closer.onClose = { [weak self] in
            window.delegate = nil
            self?.appState.keyRecoveryWindow = nil
            finished(replaced)
        }
        let sheet = RestoreSheet(
            coordinator: BackupCoordinator(container: container),
            onClose: { window.close() },
            replacing: { [weak self] in
                try self?.discardUnreadableHistory(in: context)
                replaced = true
            }
        )
        window.contentView = SafeHostingView(pesto: sheet.environment(appState))
        window.center()
        // The window and its delegate live on `AppState` until it closes: nothing else holds them.
        appState.keyRecoveryWindow = (window, closer)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
