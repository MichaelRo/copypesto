// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The first sheet: what sync does, what leaves this Mac, what iCloud can see, and the one choice about secrets.
struct SyncSetUpSheet: View {
    let controller: SyncController
    @AppStorage(Setting.syncIncludesSecrets) private var includesSecrets: Bool

    var body: some View {
        SyncSheetFrame(title: "Sync with iCloud Drive") {
            Text(verbatim: SyncCopy.intro)
            VStack(alignment: .leading, spacing: 6) {
                bullet("Encrypted files go to a folder in iCloud Drive: **\(controller.folderDisplayName)**.")
                bullet(verbatim: SyncCopy.keyLine(controller.keyMode))
                bullet(secretsLine)
                bullet("Deleting a clip on one Mac deletes it on all. Sync is not a backup.")
                bullet("iCloud can see how many Macs you have, file sizes and when files change, not your clips.")
            }
            .pestoCaption()
            Toggle("Also sync clips with secrets", isOn: $includesSecrets)
                .accessibilityIdentifier(AccessibilityID.syncSecretsToggle)
        } actions: {
            Button("Cancel", role: .cancel) { controller.cancelFlow() }.keyboardShortcut(.cancelAction)
            Button("Turn On Sync") { Task { await controller.turnOn() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.pestoProminent)
                .accessibilityIdentifier(AccessibilityID.syncTurnOnButton)
        }
    }

    private var secretsLine: LocalizedStringKey {
        controller.keepsHere == 0
            ? "Clips with secrets stay on this Mac unless you choose."
            : "Clips with secrets stay on this Mac unless you choose: **\(controller.keepsHere) clips stay here**."
    }

    private func bullet(verbatim text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\u{2022}")
            Text(verbatim: text)
        }
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\u{2022}")
            Text(text)
        }
    }
}

/// A group is already there: how many clips each side has, and that nothing is deleted.
struct SyncJoinSheet: View {
    let controller: SyncController
    let thisMac: Int
    let group: Int

    var body: some View {
        SyncSheetFrame(title: "Join sync on your other Macs") {
            Text("Pesto found sync from your other Macs in \(controller.folderDisplayName).")
            HStack(spacing: 12) {
                count(thisMac, "clips on this Mac")
                count(group, "clips already synced")
            }
            Text("Nothing is deleted. Clips are merged both ways, and the shelf stays usable while it runs.")
                .pestoCaption()
        } actions: {
            Button("Not Now", role: .cancel) { controller.cancelFlow() }.keyboardShortcut(.cancelAction)
            Button("Join and Merge") { controller.confirmJoin() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.pestoProminent)
                .accessibilityIdentifier(AccessibilityID.syncJoinButton)
        }
    }

    private func count(_ number: Int, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(number.formatted()).font(.title2.weight(.semibold))
            Text(label).pestoCaption()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct SyncFailedSheet: View {
    let controller: SyncController
    let message: String

    var body: some View {
        SyncSheetFrame(title: "Sync could not continue") {
            Text(message)
        } actions: {
            Button("Close") { controller.cancelFlow() }.keyboardShortcut(.defaultAction)
                .buttonStyle(.pestoProminent)
        }
    }
}
