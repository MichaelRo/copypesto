// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The joining Mac: these six words must match the other Mac's screen.
struct SyncPairingSheet: View {
    let controller: SyncController
    let words: [String]
    let approver: String

    var body: some View {
        SyncSheetFrame(title: "Check these six words") {
            Text("\(approver) shows a request from this Mac. Confirm both screens show the same words.")
            SyncWords(words: words)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for the other Mac to allow it\u{2026}").pestoCaption()
            }
        } actions: {
            Button("Cancel", role: .cancel) { controller.cancelFlow() }.keyboardShortcut(.cancelAction)
        }
    }
}

/// The approving Mac: a Mac wants to join; allow it only if the words match.
struct SyncApproveSheet: View {
    let controller: SyncController
    let pending: SyncPendingJoin

    var body: some View {
        SyncSheetFrame(title: "\u{201C}\(pending.request.name)\u{201D} wants to join") {
            Text("Allow it only if this Mac shows the same six words. It will be able to read your synced clips.")
            SyncWords(words: pending.words)
        } actions: {
            Button("Don\u{2019}t Allow", role: .cancel) { controller.deny(pending) }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AccessibilityID.syncDenyButton)
            Button("Allow") { controller.allow(pending) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.pestoProminent)
                .accessibilityIdentifier(AccessibilityID.syncAllowButton)
        }
    }
}

/// Shown once after sync is turned on or reset, and again from Show Recovery Key. The copy is concealed and clears
/// itself.
struct SyncRecoveryKeySheet: View {
    let controller: SyncController
    let key: String

    var body: some View {
        SyncSheetFrame(title: "Your recovery key") {
            Text(
                "This key opens your sync folder if iCloud Keychain is unavailable. Keep it in your password " +
                    "manager. Pesto cannot recover it for you."
            )
            Text(key)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
                .accessibilityIdentifier(AccessibilityID.syncRecoveryKeyText)
            RecoveryKeyActions(key: key)
        } actions: {
            Button("Done") { controller.cancelFlow() }.keyboardShortcut(.defaultAction)
                .buttonStyle(.pestoProminent)
        }
    }
}
