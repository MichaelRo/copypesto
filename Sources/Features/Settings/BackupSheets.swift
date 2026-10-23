// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI
import UniformTypeIdentifiers

private let backupFileType = UTType(filenameExtension: "pestobackup") ?? .data

/// Shown once, when a backup key is first made. Copying uses the concealed marker, so Pesto's own watcher does not save
/// the key into the history it protects.
struct RecoveryKeyNotice: View {
    let key: String
    @Binding var stored: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your recovery key").font(.headline)
            Text(key).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Text(
                "It opens this backup and every later one if you forget your passphrase, or have none. Keep it " +
                    "somewhere safe, apart from the backup, such as your password manager. You can show it again " +
                    "in Settings, Data, behind Touch ID or your password."
            )
            .pestoCaption()
            RecoveryKeyActions(key: key)
            Toggle("I have stored my recovery key", isOn: $stored)
        }
    }
}

/// Copy, or save as a text file, a recovery key. The copy is marked concealed so Pesto itself and other clipboard
/// managers do not keep it in history, and it leaves the clipboard after a while unless something else was copied.
struct RecoveryKeyActions: View {
    let key: String
    @Environment(AppState.self) private var appState: AppState
    @State private var message: String?

    var body: some View {
        HStack {
            Button("Copy Recovery Key", action: copy)
            Button("Save as File\u{2026}", action: save)
            if let message { Text(message).pestoCaption() }
        }
    }

    private func copy() {
        appState.copyRecoveryKey(key)
        message = "Copied. It clears soon."
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Pesto recovery key.txt"
        panel.allowedContentTypes = [.plainText]
        panel.message = "Save the recovery key somewhere safe, apart from your backups"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "Pesto recovery key\n\n\(key)\n\nThis key opens your Pesto backups. Keep this file private " +
            "and apart from the backups.\n"
        let saved = FileManager.default.createFile(
            atPath: url.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]
        )
        message = saved ? "Saved." : "Couldn’t save the file. Choose another folder."
    }
}

/// Shows the key again, for the person who did not keep it the first time. Opened only after Touch ID or the account
/// password.
struct RecoveryKeySheet: View {
    let key: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your recovery key").font(.title3.weight(.semibold))
            Text(key).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Text(
                "Anyone with this key and a backup file can read your clips. Keep it in your password manager, " +
                    "apart from the backups."
            )
            .pestoCaption()
            RecoveryKeyActions(key: key)
            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// What happened to the settings in a restored backup, and the changes that were held back for the person to approve.
private struct SettingsOutcome {
    var note: String
    var heldBack: [SettingsBackupManager.HeldBack] = []
    var data: Data?
}

struct RestoreSheet: View {
    private enum Phase {
        case choose
        case working
        case preview(BackupPreview)
        case done(BackupRestoreSummary, settings: SettingsOutcome?)
        case failed(String)
    }

    private enum CredentialKind: String, CaseIterable {
        case passphrase = "Passphrase"
        case recoveryKey = "Recovery key"
    }

    let coordinator: BackupCoordinator
    let onClose: () -> Void
    /// Set when the history cannot be opened: the restore discards it first, after the backup has been verified.
    var replacing: (@MainActor () throws -> Void)?
    @State private var file: URL?
    @State private var kind = CredentialKind.passphrase
    @State private var secret = ""
    @State private var phase = Phase.choose
    @State private var restoresSettings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Restore from Backup").font(.title3.weight(.semibold))
            Group {
                switch phase {
                case .choose: choose
                case .working: ProgressView("Working\u{2026}")
                case let .preview(found): previewView(found)
                case let .done(summary, settings): done(summary, settings: settings)
                case let .failed(message): failure(message)
                }
            }
            .transition(.opacity)
        }
        .animation(Motion.animation(.pestoQuick), value: phaseStep)
        .padding(20)
        .frame(width: 440)
    }

    /// Which step is showing, so a change of step fades instead of jumping.
    private var phaseStep: Int {
        switch phase {
        case .choose: 0
        case .working: 1
        case .preview: 2
        case .done: 3
        case .failed: 4
        }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Choose Backup\u{2026}", action: chooseFile)
                Text(file?.lastPathComponent ?? "No file chosen").pestoQuiet().lineLimit(1)
            }
            Picker("Open with", selection: $kind) {
                ForEach(CredentialKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if kind == .passphrase {
                SecureField("Passphrase", text: $secret)
            } else {
                TextField("Recovery key", text: $secret).font(.system(.body, design: .monospaced))
            }
            Text("Nothing is changed until you have seen what the backup holds and confirmed.")
                .pestoCaption()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onClose).keyboardShortcut(.cancelAction)
                Button("Open", action: open).keyboardShortcut(.defaultAction).disabled(file == nil || secret.isEmpty)
            }
        }
    }

    private func previewView(_ preview: BackupPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(contents(of: preview)), saved \(saved(preview)).")
            if replacing != nil {
                Text("Your current history cannot be opened on this Mac. Restoring replaces it with this backup.")
                    .font(.callout)
            } else {
                Text(
                    "Clips you already have are skipped and nothing is reordered. " +
                        "A clip you deleted is not brought back."
                )
                .pestoCaption()
            }
            if preview.settingsData != nil {
                Toggle("Restore settings too", isOn: $restoresSettings)
                    .accessibilityIdentifier(AccessibilityID.restoreSettingsToggle)
                Text(
                    "Settings that would delete history or keep less of it stay as they are on this Mac. " +
                        "The history lock, the screen-sharing blur and the excluded apps are never restored."
                )
                .pestoCaption()
            }
            if preview.warning == .olderThanThisMac {
                Label(
                    "This backup is older than the last one made on this Mac. Restoring adds its clips and "
                        + "collections to your history; check it is the one you mean.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout).foregroundStyle(Color.statusWarning)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onClose).keyboardShortcut(.cancelAction)
                Button("Restore") { restore(preview) }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func contents(of preview: BackupPreview) -> String {
        CountText.list([
            CountText.clips(preview.itemCount), CountText.collections(preview.collectionCount),
            CountText.deletions(preview.deletionCount)
        ])
    }

    private func restoredWords(_ summary: BackupRestoreSummary) -> String {
        CountText.list([CountText.clips(summary.restored), CountText.collections(summary.collections)])
    }

    private func saved(_ preview: BackupPreview) -> String {
        preview.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func done(_ summary: BackupRestoreSummary, settings: SettingsOutcome?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restored \(restoredWords(summary)). \(CountText.alreadyHere(summary.alreadyHad))")
            if let settings {
                Text(settings.note).pestoCaption()
                if !settings.heldBack.isEmpty { heldBackView(summary, settings) }
            }
            if summary
                .failed > 0 { Text("\(summary.failed) could not be restored.").foregroundStyle(Color.statusWarning) }
            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func heldBackView(_ summary: BackupRestoreSummary, _ settings: SettingsOutcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The backup also asks Pesto to delete history or keep less of it:").font(.callout)
            ForEach(settings.heldBack, id: \.key) { held in
                Text("\u{2022} \(held.description)").pestoCaption()
            }
            Button("Apply These Too") { applyHeldBack(summary, settings) }
                .accessibilityIdentifier(AccessibilityID.applyHeldBackSettings)
        }
    }

    private func applyHeldBack(_ summary: BackupRestoreSummary, _ settings: SettingsOutcome) {
        guard let data = settings.data else { return }
        let note = if (try? SettingsBackupManager.restore(from: data, approving: Set(settings.heldBack.map(\.key)))) !=
            nil
        {
            String(localized: "Settings restored.")
        } else {
            String(localized: "The settings in the backup could not be read, so they were left as they are.")
        }
        phase = .done(summary, settings: SettingsOutcome(note: note))
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
            HStack {
                Spacer()
                Button("Back") { phase = .choose }
                Button("Close", action: onClose)
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [backupFileType, .data]
        panel.allowsMultipleSelection = false
        let configuration = RuntimeConfiguration.current
        if configuration.mode == .uiTest, configuration.keyLossFixture {
            // A UI test cannot drive the file panel: the lost-key flow's fixture backup stands in for the choice.
            file = AppPaths.supportDirectory.appendingPathComponent(KeyLossFixture.fileName)
            return
        }
        if panel.runModal() == .OK { file = panel.url }
    }

    private func open() {
        guard let file else { return }
        phase = .working
        Task {
            do {
                let credential: BackupCredential = try kind == .passphrase
                    ? .passphrase(secret) : .recoveryKey(BackupKey(recoveryKey: secret))
                phase = try await .preview(coordinator.open(file, credential: credential))
            } catch {
                phase = .failed(BackupMessages.text(for: error))
            }
        }
    }

    /// What to tell the person about the settings, or nil when there is nothing to say.
    private func restoreSettingsIfAsked(from preview: BackupPreview) -> SettingsOutcome? {
        guard restoresSettings, let data = preview.settingsData else { return nil }
        guard let result = try? SettingsBackupManager.restore(from: data) else {
            return SettingsOutcome(
                note: String(localized: "The settings in the backup could not be read, so they were left as they are.")
            )
        }
        guard !result.heldBack.isEmpty else { return SettingsOutcome(note: String(localized: "Settings restored.")) }
        let held = result.heldBack.count
        return SettingsOutcome(
            note: String(localized: "Settings restored, except \(held) that would delete history or keep less of it."),
            heldBack: result.heldBack, data: data
        )
    }

    private func restore(_ preview: BackupPreview) {
        phase = .working
        Task {
            do {
                let summary = if let replacing {
                    try await coordinator.restore(preview, replacing: replacing)
                } else {
                    try await coordinator.restore(preview)
                }
                phase = .done(summary, settings: restoreSettingsIfAsked(from: preview))
            } catch {
                phase = .failed("Couldn’t restore. \(error.localizedDescription)")
            }
        }
    }
}
