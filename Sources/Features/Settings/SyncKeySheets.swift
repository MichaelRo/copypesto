// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Sync needs iCloud Keychain and it is off (or has not delivered the key).
struct SyncKeychainOffSheet: View {
    let controller: SyncController

    var body: some View {
        SyncSheetFrame(title: "iCloud Keychain Is Off") {
            Text("Sync needs iCloud Keychain to share its key between your Macs. Nothing has been sent.")
            Text("Turn it on in System Settings, or join with a recovery key instead.").pestoCaption()
        } actions: {
            Button("Enter Recovery Key\u{2026}") { controller.beginRecoveryKeyEntry() }
            Button("Open System Settings") { SystemSettingsLink.openAppleAccount() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.pestoProminent)
        }
    }
}

/// A build or folder without iCloud Keychain: the key comes from another Mac or from a recovery key.
struct SyncNeedsKeySheet: View {
    let controller: SyncController

    var body: some View {
        SyncSheetFrame(title: "This Mac needs the key") {
            Text("This Mac cannot get the key from iCloud Keychain, so another Mac has to hand it over.")
            option("Ask another Mac", "It shows a request, and you check that six words match.")
            option("Enter a recovery key", "The key you saved when sync was turned on.")
        } actions: {
            Button("Cancel", role: .cancel) { controller.cancelFlow() }.keyboardShortcut(.cancelAction)
            Button("Enter Recovery Key\u{2026}") { controller.beginRecoveryKeyEntry() }
            Button("Ask Another Mac\u{2026}") { controller.askAnotherMac() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.pestoProminent)
                .accessibilityIdentifier(AccessibilityID.syncAskAnotherMacButton)
        }
    }

    private func option(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).pestoCaption()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct SyncEnterKeySheet: View {
    let controller: SyncController
    @State private var text = ""

    var body: some View {
        SyncSheetFrame(title: "Enter the recovery key") {
            Text("The key shown when sync was turned on, or after Reset Sync.")
            TextField("Recovery key", text: $text)
                .font(.system(.body, design: .monospaced))
                .accessibilityIdentifier(AccessibilityID.syncRecoveryKeyField)
        } actions: {
            Button("Cancel", role: .cancel) { controller.cancelFlow() }.keyboardShortcut(.cancelAction)
            Button("Continue") { Task { await controller.useRecoveryKey(text) } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.pestoProminent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
