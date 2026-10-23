// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Clear Everything, last in Data: it removes the history, the collections and the snippets, and it is the one place
/// that has to say what happens to a backup (kept and paused, or deleted with it).
struct StartOverSettings: View {
    @Environment(AppState.self) private var appState: AppState
    @State private var snapshot: PrivacySnapshot?
    @State private var confirmingClear = false
    @State private var message: String?

    private var startOverMessage: String {
        let clipCount = snapshot?.clipCount ?? 0
        var message = String(localized: "This deletes all \(clipCount) clips, including pinned ones.")
        message += " Every collection and snippet goes too. It can\u{2019}t be undone."
        if hasBackup {
            message += " Keeping the backup leaves its file as it is and pauses automatic backup until you resume it;"
            message += " deleting it removes the file too."
        }
        return message
    }

    private var hasBackup: Bool {
        AutoBackupSettings().isEnabled
    }

    var body: some View {
        Section {
            Button("Clear Everything…", role: .destructive) { confirmingClear = true }
                .accessibilityIdentifier(AccessibilityID.clearEverythingButton)
                .settingsRow("Clear Everything")
            if let message { Text(message).pestoCaption() }
        } header: {
            Text("Start over")
        } footer: {
            Text(
                "Removes every clip, pinned ones too, every collection and every snippet, along with previews " +
                    "and the last-clip file. Your settings stay. It asks for Touch ID or your password first."
            )
        }
        .task { snapshot = await appState.privacySnapshot?() }
        .alert("Clear everything?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            if hasBackup {
                Button("Clear and Keep Backup") { Task { await clearEverything(deleteBackup: false) } }
                Button("Clear and Delete Backup", role: .destructive) {
                    Task { await clearEverything(deleteBackup: true) }
                }
            } else {
                Button("Clear Everything", role: .destructive) { Task { await clearEverything(deleteBackup: false) } }
            }
        } message: {
            Text(startOverMessage)
        }
    }

    private func clearEverything(deleteBackup: Bool) async {
        let authenticator = UserAuthenticator.current
        if authenticator.canAuthenticate(),
           await !AuthenticationGrace.shared.verify(
               using: authenticator, reason: "Clear everything Pesto has saved", requireFresh: true
           )
        {
            message = "Nothing was cleared."
            return
        }
        do {
            let removed = try await appState.clearEverything?() ?? 0
            AutoBackupHolder.service?.afterClearEverything(deleteBackup: deleteBackup)
            message = String(localized: "Cleared \(removed) clips.")
        } catch {
            message = "Couldn\u{2019}t clear everything: \(error.localizedDescription)"
        }
        snapshot = await appState.privacySnapshot?()
    }
}
