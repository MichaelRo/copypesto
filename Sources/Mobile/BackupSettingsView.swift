// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Settings → Data → Backup (ADR 0078): a backup made by hand and kept where the person chooses in Files, and a
/// restore from any backup file. Nothing runs on a schedule and no folder is remembered.
struct BackupSettingsView: View {
    @Environment(MobileAppState.self) private var appState
    @State private var lastBackup = Date.distantPast
    @State private var isBackingUp = false
    @State private var isChoosingFile = false
    @State private var restoring: RestoreFile?
    @State private var hasKey = false
    @State private var revealedKey: RevealedKey?

    private struct RestoreFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct RevealedKey: Identifiable {
        let id = UUID()
        let key: String
    }

    var body: some View {
        Form {
            Section {
                Button("Back Up Now\u{2026}") { isBackingUp = true }
                    .accessibilityIdentifier(MobileAccessibilityID.backUpNowButton)
                Button("Restore from Backup\u{2026}") { isChoosingFile = true }
                    .accessibilityIdentifier(MobileAccessibilityID.restoreBackupButton)
            } footer: {
                Text(footer)
            }
            if hasKey {
                Section {
                    Button("Show Recovery Key\u{2026}") {
                        Task {
                            if let key = await appState
                                .revealBackupRecoveryKey() { revealedKey = RevealedKey(key: key) }
                        }
                    }
                    .accessibilityIdentifier(MobileAccessibilityID.showBackupRecoveryKeyButton)
                } footer: {
                    Text(
                        "The recovery key opens every backup this device makes. " +
                            "Pesto asks for Face ID or your passcode first."
                    )
                }
            }
        }
        .navigationTitle("Backup")
        .onAppear(perform: refresh)
        .sheet(isPresented: $isBackingUp, onDismiss: refresh) {
            BackupNowSheet()
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [BackupFileType.utType, .data]) { result in
            if case let .success(url) = result { restoring = RestoreFile(url: url) }
        }
        .sheet(item: $restoring) { file in
            RestoreBackupSheet(file: file.url)
        }
        .alert(
            "Your Recovery Key", isPresented: Binding(
                get: { revealedKey != nil },
                set: { if !$0 { revealedKey = nil } }
            ),
            presenting: revealedKey
        ) { revealed in
            Button("Copy") { MobileClipboard.write(.text(revealed.key), protected: true) }
            Button("Done", role: .cancel) {}
        } message: { revealed in
            Text(revealed.key).monospaced()
        }
    }

    private func refresh() {
        hasKey = appState.hasBackupKey
        lastBackup = AppDefaults.store.value(for: Setting.lastManualBackup)
    }

    private var footer: String {
        let lead = String(localized: "A backup is one encrypted file you keep in Files, such as iCloud Drive.") + " "
            + String(localized: "Restore takes a backup from this device or from a Mac. Settings stay on each device.")
        guard lastBackup > .distantPast else { return lead }
        let date = lastBackup.formatted(date: .abbreviated, time: .shortened)
        return lead + " " + String(localized: "Last saved \(date).")
    }
}
