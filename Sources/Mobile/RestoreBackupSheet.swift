// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Restore from Backup (ADR 0078): any `.pestobackup`, a Mac's included, opened with its passphrase or recovery key,
/// shown, and mixed in only after the person confirms. Clips already here are skipped and nothing is reordered.
struct RestoreBackupSheet: View {
    let file: URL
    @Environment(MobileAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.passphrase
    @State private var secret = ""
    @State private var phase = Phase.credential
    @State private var problem: String?

    private enum Kind: Hashable {
        case passphrase
        case recoveryKey
    }

    private enum Phase {
        case credential
        case working
        case preview(BackupPreview, BackupRestorePreview?)
        case done(BackupRestoreSummary)
    }

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle("Restore from Backup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if case .done = phase {
                            Button("Done") { dismiss() }
                        } else {
                            Button("Cancel") { dismiss() }.disabled(isWorking)
                        }
                    }
                }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .credential: credential
        case .working: Section { HStack { ProgressView()
                Text("Working\u{2026}")
            } }
        case let .preview(preview, counts): previewView(preview, counts: counts)
        case let .done(summary): Section { Text(BackupText.restored(summary)) }
        }
    }

    @ViewBuilder
    private var credential: some View {
        Section {
            LabeledContent("File", value: file.lastPathComponent)
            Picker("Open with", selection: $kind) {
                Text("Passphrase").tag(Kind.passphrase)
                Text("Recovery Key").tag(Kind.recoveryKey)
            }
            .pickerStyle(.segmented)
            if kind == .passphrase {
                SecureField("Passphrase", text: $secret).textContentType(.password)
            } else {
                TextField("Recovery key", text: $secret, axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
        } footer: {
            Text(problem ??
                String(localized: "Nothing is changed until you have seen what the backup holds and confirmed."))
                .foregroundStyle(problem == nil ? Color.secondary : Color.statusBad)
        }
        Section {
            Button("Open", action: open).disabled(secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func previewView(_ preview: BackupPreview, counts: BackupRestorePreview?) -> some View {
        Section {
            ForEach(Array(BackupText.previewLines(preview, counts: counts).enumerated()), id: \.offset) { index, line in
                Text(line).foregroundStyle(index == 0 ? Color.primary : Color.secondary)
            }
            if preview.warning == .olderThanThisMac {
                Label(
                    "This backup is older than the last one saved from this device. Check it is the one you mean.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(Color.statusWarning)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "Clips you already have are skipped and nothing is reordered. " +
                        "A clip you deleted is not brought back."
                )
                if preview.settingsData != nil {
                    Text(
                        "This backup holds a Mac\u{2019}s settings too. " +
                            "They are not used here; your settings stay as they are."
                    )
                }
            }
        }
        Section {
            Button("Restore") { restore(preview) }
        }
    }

    private func open() {
        problem = nil
        let typed = secret
        let chosen = kind
        phase = .working
        Task {
            do {
                let credential: BackupCredential = try chosen == .passphrase
                    ? .passphrase(typed) : .recoveryKey(BackupKey(recoveryKey: typed))
                let preview = try await appState.openBackup(at: file, credential: credential)
                let counts = await appState.restorePreview(preview)
                secret = ""
                phase = .preview(preview, counts)
            } catch is CancellationError {
                dismiss()
            } catch {
                problem = BackupText.openFailure(error)
                phase = .credential
            }
        }
    }

    private func restore(_ preview: BackupPreview) {
        phase = .working
        Task {
            if let summary = await appState.restoreBackup(preview) {
                phase = .done(summary)
            } else {
                dismiss()
            }
        }
    }
}
