// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

/// The share extension's inbox (ADR 0047): each time Pesto comes to the front it publishes its inbox key in the app
/// group and adds what was shared while it was away, through ingest. A hosted test drives `drainInbox` itself; a
/// UI-test launch keeps the key in memory and the inbox in its own folder.
extension MobileAppState {
    private static let inboxLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "Inbox")
    private static let uiTestSecrets = InMemorySecretStore()

    func inboxDidBecomeActive() {
        let mode = LaunchMode.current
        guard mode != .hostedTests, let inbox = SharedInbox.current else { return }
        let keys = InboxKeyStore(secrets: mode == .uiTest ? Self.uiTestSecrets : KeychainSecretStore())
        Task { await drainInbox(inbox, keys: keys) }
    }

    @discardableResult
    func drainInbox(_ inbox: SharedInbox, keys: InboxKeyStore) async -> InboxDrain.Report? {
        guard !isHistoryLockedNow() else { return nil }
        if let running = inboxDrain { return await running.value }
        let task = Task<InboxDrain.Report?, Never> { [self] in
            await runInboxDrain(inbox, keys: keys)
        }
        inboxDrain = task
        let report = await task.value
        inboxDrain = nil
        return report
    }

    private func runInboxDrain(_ inbox: SharedInbox, keys: InboxKeyStore) async -> InboxDrain.Report? {
        guard let service = storageService else { return nil }
        let drain: InboxDrain
        do {
            let privateKey = try keys.loadOrCreate()
            try inbox.publish(InboxPublicKey(privateKey.publicKey))
            drain = InboxDrain(inbox: inbox, privateKey: privateKey)
        } catch {
            Self.inboxLogger.error("The inbox key is unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let report = await drain.run(into: service)
        if report.problems > 0 {
            tell(String(localized: "\(report.problems) shared clips couldn\u{2019}t be added."), isProblem: true)
        }
        return report
    }
}
