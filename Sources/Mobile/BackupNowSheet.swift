// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Back Up Now (ADR 0078): how the file is protected, then the file is written, the recovery key shown when it is
/// new, and Files asked where to keep it. The file waits in the temporary folder only while this sheet is open.
struct BackupNowSheet: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var protection = AutoBackupSettings.Protection.passphrase
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var includeHidden = false
    @State private var isWorking = false
    @State private var file: MobileBackupFile?
    @State private var storedKey = false
    @State private var copiedKey = false
    @State private var isExporting = false
    @State private var wasSaved = false

    var body: some View {
        NavigationStack {
            Form {
                if let file { ready(file) } else { protectionForm }
            }
            .navigationTitle("Back Up Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
            }
            .sheet(isPresented: $isExporting) {
                if let file {
                    BackupExportPicker(
                        file: file.url,
                        onSaved: {
                            wasSaved = true
                            appState.backupSaved(file)
                            dismiss()
                        },
                        onCancel: { isExporting = false }
                    )
                    .ignoresSafeArea()
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .onDisappear {
            if let file, !wasSaved { appState.backupNotSaved(file) }
        }
    }

    @ViewBuilder
    private var protectionForm: some View {
        Section {
            Picker("Protect with", selection: $protection) {
                Text("Passphrase").tag(AutoBackupSettings.Protection.passphrase)
                Text("Recovery Key Only").tag(AutoBackupSettings.Protection.recoveryKey)
            }
            .pickerStyle(.segmented)
            if protection == .passphrase {
                SecureField("Passphrase", text: $passphrase)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier(MobileAccessibilityID.backupPassphraseField)
                SecureField("Passphrase Again", text: $confirmation)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier(MobileAccessibilityID.backupConfirmField)
            }
        } footer: {
            if protection == .passphrase {
                Text(BackupText.passphraseHint(passphrase, confirmation: confirmation))
            } else {
                Text("Only the recovery key opens this backup. Pesto shows it next; keep it in your password manager.")
            }
        }
        Section {
            Toggle("Include Clips with Secrets", isOn: $includeHidden)
        } footer: {
            Text(
                "Card numbers, keys and other hidden clips stay out unless you include them. Copies kept from a " +
                    "password manager are never included. The file is encrypted; settings stay on this device."
            )
        }
        Section {
            Button {
                start()
            } label: {
                if isWorking {
                    HStack { ProgressView()
                        Text("Backing Up\u{2026}")
                    }
                } else {
                    Text("Back Up")
                }
            }
            .disabled(isWorking || !BackupText.canBackUp(
                protection: protection, passphrase: passphrase, confirmation: confirmation
            ))
            .accessibilityIdentifier(MobileAccessibilityID.backupStartButton)
        }
    }

    @ViewBuilder
    private func ready(_ file: MobileBackupFile) -> some View {
        Section {
            Text(BackupText.written(file.summary))
            ForEach(BackupText.leftOut(file.summary), id: \.self) { Text($0).foregroundStyle(.secondary) }
        }
        if let key = file.recoveryKey {
            Section {
                Text(key)
                    .font(.body.monospaced())
                    .accessibilityIdentifier(MobileAccessibilityID.backupRecoveryKey)
                Button {
                    MobileClipboard.write(.text(key), protected: true)
                    copiedKey = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedKey = false
                    }
                } label: {
                    Label(copiedKey ? "Copied" : "Copy", systemImage: copiedKey ? "checkmark" : "doc.on.doc")
                }
                Toggle("I Have Stored the Recovery Key", isOn: $storedKey)
            } header: {
                Text("Your Recovery Key")
            } footer: {
                Text(
                    "It opens every backup this device makes, even if you forget the passphrase. A copy stays on " +
                        "this device and leaves the clipboard after two minutes."
                )
            }
        }
        Section {
            Button("Save to Files\u{2026}") { isExporting = true }
                .disabled(file.recoveryKey != nil && !storedKey)
        } footer: {
            Text("Choose iCloud Drive or another place that is not only on this device.")
        }
    }

    private func start() {
        isWorking = true
        Task {
            defer { isWorking = false }
            file = await appState.backUp(
                protection: protection, passphrase: passphrase, includeHidden: includeHidden
            )
            if file != nil {
                passphrase = ""
                confirmation = ""
            }
        }
    }
}
