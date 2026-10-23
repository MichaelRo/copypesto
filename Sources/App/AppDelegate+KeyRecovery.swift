// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import SwiftData

extension AppDelegate {
    /// Runs `then` (the rest of launch) once the history can be used: at once when its key is fine, after the person
    /// has
    /// answered the "can't unlock" alert otherwise, and never when they quit. The recovery is event-driven, not modal:
    /// a
    /// modal session did not run the restore window's async work (`KeyLossRecoveryUITests`).
    func resolveMissingEncryptionKey(then: @escaping () -> Void) {
        let forced = RuntimeConfiguration.current.mode == .uiTest && RuntimeConfiguration.current.keyLossFixture
        guard forced || LaunchMode.current.usesSystemIntegrations,
              let container = appState.historyContainer else { return then() }
        let context = ModelContext(container)
        if forced {
            // A UI test cannot lose the Keychain key or drive a file panel, so the restore window finds the backup
            // written here instead of asking for a file. The alert comes just after launch finishes (a modal alert
            // inside
            // launch keeps XCUITest from ever seeing the app as launched), so here launch goes on first and a test uses
            // the empty seed.
            try? KeyLossFixture.write(to: AppPaths.supportDirectory.appendingPathComponent(KeyLossFixture.fileName))
            DispatchQueue.main.async { [self] in
                askAboutLostKey(decision: .keyMissingWithExistingData, container: container, context: context) {}
            }
            return then()
        }
        let blobCount = (try? context.fetchCount(FetchDescriptor<ClipboardBlob>())) ?? 0
        let previewCount = (try? context.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.previewCiphertext != nil }
        ))) ?? 0
        let presence = BlobEncryption.keyPresence()
        let decision = KeyStartupDecision.evaluate(
            presence: presence,
            encryptedRowCount: blobCount + previewCount,
            canaryOpens: presence == .present ? Self.keyOpensSomeHistory(in: context) : nil
        )
        if decision == .keychainUnavailable { return waitForKeychain(then: then) }
        guard decision == .keyMissingWithExistingData || decision == .keyDoesNotOpenHistory else { return then() }
        BlobEncryption.setMintingLocked(true)
        appState.isEncryptionKeyUnresolved = true
        Self.logger.error("Encryption key missing or wrong while encrypted history exists; refusing to mint a new key")
        askAboutLostKey(decision: decision, container: container, context: context, then: then)
    }

    private func askAboutLostKey(
        decision: KeyStartupDecision,
        container: ModelContainer,
        context: ModelContext,
        then: @escaping () -> Void
    ) {
        NSApp.activate()
        let alert = Self.keyLossAlert(missing: decision == .keyMissingWithExistingData)
        let choice = KeyLossChoice(buttonIndex: alert.runModal().rawValue - NSApplication.ModalResponse
            .alertFirstButtonReturn.rawValue)
        if choice.opensRestore {
            // Nothing is wiped unless a backup opens and the person confirms; any other way out comes back here.
            showKeyRecoveryRestore(container: container, context: context) { [self] replaced in
                guard replaced else {
                    return askAboutLostKey(decision: decision, container: container, context: context, then: then)
                }
                appState.isEncryptionKeyUnresolved = false
                then()
            }
            return
        }
        guard choice.startsOver else { return NSApp.terminate(nil) }
        do {
            try discardUnreadableHistory(in: context)
        } catch {
            Self.logger.error("Could not clear unreadable history: \(error.localizedDescription, privacy: .public)")
            return NSApp.terminate(nil)
        }
        appState.isEncryptionKeyUnresolved = false
        then()
    }

    private static func keyLossAlert(missing: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Pesto can’t unlock your clipboard history")
        alert.informativeText = (missing
            ? String(localized: """
            The encryption key for your history is no longer in this Mac’s Keychain, which can happen \
            after a Keychain reset or a restore from another Mac.
            """)
            : String(localized: """
            The encryption key in this Mac’s Keychain does not open your history, which can happen \
            after a Keychain reset or a restore from another Mac.
            """))
            + " "
            + String(localized: """
            Existing clips can’t be recovered from this Mac. Quit to try restoring the key first, \
            restore from a backup, or start again with an empty history.
            """)
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Start With Empty History"))
        alert.addButton(withTitle: String(localized: "Restore from Backup\u{2026}"))
        return alert
    }

    /// Removes the rows the missing key made unreadable and lets a new key be made. Used by Start With Empty History
    /// and,
    /// once a backup has been verified and confirmed, by Restore from Backup.
    func discardUnreadableHistory(in context: ModelContext) throws {
        try UnreadableHistory.discard(in: context)
        storageService?.undoHistory.clear()
        // The file the CLI reads holds the latest clip's preview: an emptied history must not leave it behind.
        FileLastItemStore().clear()
        BlobEncryption.setMintingLocked(false)
    }

    /// A locked or unreachable Keychain is not a lost key: never offer to wipe. The person can try again once it is
    /// available, or quit with the history untouched.
    private func waitForKeychain(then: @escaping () -> Void) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Pesto can’t reach your Keychain")
        alert.informativeText = String(localized: """
        Pesto keeps the key to your clipboard history in the Keychain, and it isn’t available \
        right now (it may be locked). Your history has not been changed.
        """)
        alert.addButton(withTitle: String(localized: "Try Again"))
        alert.addButton(withTitle: String(localized: "Quit"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            appState.isEncryptionKeyUnresolved = true
            return NSApp.terminate(nil)
        }
        resolveMissingEncryptionKey(then: then)
    }

    /// Whether the key opens at least one stored row. Looks at a few, so one damaged row does not count as a wrong key.
    /// The smallest clips are tried, not the first five stored: this runs at launch on the main thread, and five
    /// pictures
    /// of 100 MB would be read and decrypted before the shelf could open.
    static func keyOpensSomeHistory(in context: ModelContext) -> Bool? {
        var descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.byteSize)])
        descriptor.fetchLimit = 5
        guard let items = try? context.fetch(descriptor) else { return nil }
        let blobs = items.compactMap(\.blob)
        guard !blobs.isEmpty else { return nil }
        return blobs.contains { $0.decryptedData() != nil }
    }
}
