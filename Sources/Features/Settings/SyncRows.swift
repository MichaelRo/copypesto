// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The Sync half of the Backup and Sync group: the switch with what it is not, the real state, where the copies live,
/// where the key lives, and Reset Sync and Leave Sync. There is no list of Macs here or anywhere.
struct SyncRows: View {
    let controller: SyncController
    @State private var confirmsReset = false
    @State private var confirmsLeave = false

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Sync with my other Macs", isOn: Binding(
                    get: { controller.isEnabled },
                    set: { on in if on { controller.beginSetUp() } else { controller.pause() } }
                ))
                .accessibilityIdentifier(AccessibilityID.syncSwitch)
                .settingsRow("Sync with my other Macs")
                Text(
                    "Keeps the Macs where you turn this on matching. Deleting a clip on one deletes it on all. " +
                        "Sync is not a backup."
                )
                .pestoCaption()
                if controller.isEnabled { statusLine }
            }
            if controller.isEnabled { details }
        }
        .confirmationDialog("Reset Sync?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Sync", role: .destructive) { Task { await controller.reset() } }
        } message: {
            Text(
                "Every Mac gets a new key. A Mac you removed from your Apple Account stops receiving clips. This Mac " +
                    "keeps everything it has, and your other Macs join again on their next launch."
            )
        }
        .confirmationDialog("Leave Sync on this Mac?", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("Leave Sync", role: .destructive) { controller.leave() }
        } message: {
            Text(
                "This Mac stops syncing and removes its own files from the folder. Your other Macs keep everything. " +
                    "Clips already on this Mac stay."
            )
        }
    }

    private var statusLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(controller.status.dotColor).frame(width: 8, height: 8).accessibilityHidden(true)
            Text("\(controller.status.title). \(controller.status.detail)").font(.callout)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.syncStatus)
    }

    @ViewBuilder
    private var details: some View {
        HStack(spacing: 8) {
            Text("Where your copies live")
            Spacer(minLength: 12)
            Text(controller.folderURL.lastPathComponent).pestoQuiet().lineLimit(1).truncationMode(.middle)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([controller.folderURL]) }
            Button("Change\u{2026}") { Task { await changeFolder() } }
                .accessibilityIdentifier(AccessibilityID.syncChangeFolderButton)
        }
        HStack(spacing: 8) {
            Text("Sync key")
            Spacer(minLength: 12)
            Text(controller.keyMode == .iCloudKeychain ? "iCloud Keychain" : "This Mac").pestoQuiet()
            Button("Show Recovery Key\u{2026}") { Task { await showRecoveryKey() } }
        }
        HStack(spacing: 8) {
            Button("Pause Sync") { controller.pause() }.accessibilityIdentifier(AccessibilityID.syncPauseButton)
            Spacer()
            Button("Reset Sync\u{2026}", role: .destructive) { Task { await ask(reset: true) } }
                .accessibilityIdentifier(AccessibilityID.syncResetButton)
            Button("Leave Sync\u{2026}", role: .destructive) { Task { await ask(reset: false) } }
                .accessibilityIdentifier(AccessibilityID.syncLeaveButton)
        }
    }

    private func ask(reset: Bool) async {
        guard await ProtectedAction.permitted(reason: "Reset or leave Pesto sync") else { return }
        if reset { confirmsReset = true } else { confirmsLeave = true }
    }

    private func changeFolder() async {
        guard await ProtectedAction.permitted(reason: "Move Pesto sync to another folder") else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = controller.folderURL.deletingLastPathComponent()
        panel.prompt = "Choose"
        panel.message = "Choose the folder for the sync files"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        controller.changeFolder(to: folder)
    }

    private func showRecoveryKey() async {
        guard await HistoryLockPolicy.permitsSensitiveAction(
            using: UserAuthenticator.current, reason: "Show the recovery key for Pesto sync", requireFresh: true
        ) else { return }
        controller.presentRecoveryKey()
    }
}

/// Presents whichever sync screen the controller is on, and the request to allow another Mac, as sheets.
struct SyncSheetHost: ViewModifier {
    let controller: SyncController?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { controller.map { $0.flow != .idle } ?? false },
                set: { if !$0 { controller?.cancelFlow() } }
            )) {
                if let controller { flowSheet(controller) }
            }
            .sheet(isPresented: Binding(
                get: { controller?.pendingJoin != nil && controller?.flow == .idle },
                set: { _ in }
            )) {
                if let controller, let pending = controller.pendingJoin { SyncApproveSheet(
                    controller: controller,
                    pending: pending
                ) }
            }
            .task(id: controller?.isEnabled) {
                while !Task.isCancelled {
                    controller?.refresh()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
    }

    @ViewBuilder
    private func flowSheet(_ controller: SyncController) -> some View {
        switch controller.flow {
        case .idle: EmptyView()
        case .setUp: SyncSetUpSheet(controller: controller)
        case let .joinOffer(thisMac, group): SyncJoinSheet(controller: controller, thisMac: thisMac, group: group)
        case .iCloudKeychainOff: SyncKeychainOffSheet(controller: controller)
        case .needsKey: SyncNeedsKeySheet(controller: controller)
        case let .pairing(words, approver): SyncPairingSheet(controller: controller, words: words, approver: approver)
        case .enterRecoveryKey: SyncEnterKeySheet(controller: controller)
        case let .recoveryKey(key): SyncRecoveryKeySheet(controller: controller, key: key)
        case let .failed(message): SyncFailedSheet(controller: controller, message: message)
        }
    }
}

extension View {
    func syncSheets(_ controller: SyncController?) -> some View {
        modifier(SyncSheetHost(controller: controller))
    }
}
