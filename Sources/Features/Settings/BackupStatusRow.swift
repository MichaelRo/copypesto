// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The first row of Backup: whether it is on, paused or off, what it last did, and the one thing to do next. It
/// replaces working that out from which buttons were showing.
struct BackupStatusRow: View {
    @Environment(\.pestoAccent) private var accent
    let status: BackupStatus
    let lastBackup: Date?
    let lastBytes: Int
    let isWorking: Bool
    /// Raised each time a backup finishes, so the dot answers once.
    let pulse: Int
    let onBackUpNow: () -> Void
    let onResume: () -> Void
    let onSetUp: () -> Void
    let onRestore: () -> Void
    @State private var pulsing = false

    private var dotColor: Color {
        switch status {
        case .on: .statusGood
        case .paused: .orange
        case .off: .secondary
        }
    }

    private var detail: String {
        switch status {
        case .on:
            guard lastBackup != nil else {
                return String(localized: "No backup has been written yet. It updates by itself after you copy.")
            }
            let when = BackupStatus.lastBackupText(lastBackup)
            return String(localized: "Last backup \(when), \(BackupMessages.size(lastBytes)).")
        case .paused:
            return String(localized: """
            You cleared everything and kept the backup, so it still holds your old clips. \
            Automatic backup waits until you choose.
            """)
        case .off:
            return String(localized: """
            Back up your clips, collections, snippets and settings to one encrypted file you can restore on any Mac.
            """)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .scaleEffect(pulsing ? 1.5 : 1)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(status.title)).font(.headline)
                Text(detail).pestoCaption()
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.backupStatus)
        .onChange(of: pulse) { _, _ in
            withAnimation(Motion.animation(.pestoPop)) { pulsing = true }
            Task {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(Motion.animation(.pestoWash)) { pulsing = false }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .on:
            Button("Back Up Now", action: onBackUpNow)
                .disabled(isWorking)
                .accessibilityIdentifier(AccessibilityID.autoBackupNowButton)
        case .paused:
            VStack(alignment: .trailing, spacing: 6) {
                Button("Resume Backup\u{2026}", action: onResume)
                    .accessibilityIdentifier(AccessibilityID.resumeBackupButton)
                Button("Restore\u{2026}", action: onRestore)
                    .accessibilityIdentifier(AccessibilityID.restoreBackupButton)
            }
        case .off:
            HStack {
                Button("Set Up Backup\u{2026}", action: onSetUp)
                    .accessibilityIdentifier(AccessibilityID.setUpBackupButton)
                Button("Restore\u{2026}", action: onRestore)
                    .accessibilityIdentifier(AccessibilityID.restoreBackupButton)
            }
        }
    }
}
