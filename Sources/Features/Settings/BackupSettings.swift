// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI

/// Settings → Data → Backup: a summary of where the clips are, one switch for "Back up this Mac", and what it keeps.
/// The backup is one encrypted file for this Mac, in a folder the person chose (iCloud Drive is suggested), protected
/// by a passphrase or a recovery key, kept up to date by itself unless they say otherwise (ADR 0019). Off until set up,
/// and per Mac: turning it off is how a work Mac stays out of it. Restoring is always a deliberate act.
struct BackupSettings: View {
    private enum ActiveSheet: Identifiable {
        case setUp
        case restore
        case recoveryKey(String)

        var id: String {
            switch self {
            case .setUp: "setUp"
            case .restore: "restore"
            case .recoveryKey: "recoveryKey"
            }
        }
    }

    @Environment(AppState.self) private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var sheet: ActiveSheet?
    @State private var isConfigured = AutoBackupSettings().isEnabled
    @State private var paused = AutoBackupSettings().pausedAfterClear
    @State private var pulse = 0
    @State private var automatic = AutoBackupSettings().runsAutomatically
    @State private var includesSecrets = AutoBackupSettings().includesSecrets
    @State private var problem = AutoBackupSettings().problem
    @State private var lastBackup = AutoBackupSettings().lastBackup
    @State private var confirmsTurningOff = false
    @State private var hasRecoveryKey = Self.storedKeyExists()
    @State private var status: String?
    @State private var working = false
    @State private var confirmsReplacement = false
    @State private var unreadableCount = 0
    @State private var confirmsDeletingUnreadable = false
    @State private var now = Date.now
    private let settings = AutoBackupSettings()

    var body: some View {
        Section {
            BackupSummaryRow(chip: chip, now: now)
            backupSwitch
            if isConfigured {
                BackupStatusLine(
                    chip: chip, lastBytes: settings.lastBytes, lastMessage: status, isWorking: working, pulse: pulse,
                    onBackUpNow: { Task { await backUpNow() } },
                    onResume: { confirmsReplacement = true }
                )
                if automatic, lastBackup != nil, let nextText { Text(nextText).pestoCaption() }
                if !automatic { Text("Only when you choose Back Up Now.").pestoCaption() }
                configured
            } else {
                if let status { Text(status).pestoCaption() }
                if hasRecoveryKey { recoveryKeyRow }
            }
            restoreRow
            if unreadableCount > 0 {
                Button("Delete Unreadable Clips\u{2026}", role: .destructive) { confirmsDeletingUnreadable = true }
                    .accessibilityIdentifier(AccessibilityID.deleteUnreadableClipsButton)
            }
            if hasRecoveryKey, let explanation = appState.authenticationAvailability.explanation {
                Text(explanation).pestoCaption()
            }
        } header: {
            Text("Backup").settingsRow("Backup")
        } footer: {
            Text(footerText)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let nowPaused = settings.pausedAfterClear
            if paused != nowPaused { paused = nowPaused }
            let nowConfigured = settings.isEnabled
            if isConfigured != nowConfigured { isConfigured = nowConfigured }
            if problem != settings.problem { problem = settings.problem }
            if lastBackup != settings.lastBackup { lastBackup = settings.lastBackup }
        }
        .confirmationDialog(
            "Turn off backup on this Mac?", isPresented: $confirmsTurningOff, titleVisibility: .visible
        ) {
            Button("Turn Off Backup", role: .destructive, action: removeBackup)
        } message: {
            Text(
                "The file stays in its folder; delete it in Finder if you no longer want it. " +
                    "Your other Macs\u{2019} files are never changed."
            )
        }
        .confirmationDialog(
            "Delete the clips that cannot be opened?", isPresented: $confirmsDeletingUnreadable,
            titleVisibility: .visible
        ) {
            Button("Delete Clips", role: .destructive) { Task { await deleteUnreadableClips() } }
        } message: {
            Text(
                "They cannot be pasted or backed up. A backup made earlier can still bring a readable copy back."
            )
        }
        .confirmationDialog(
            "Replace the backup with the current history?", isPresented: $confirmsReplacement, titleVisibility: .visible
        ) {
            Button("Replace Backup", role: .destructive) { Task { await backUpNow(allowShrink: true) } }
        } message: {
            Text(
                "The backup in the folder holds more than your history does now. " +
                    "The old file is kept as a previous copy."
            )
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .setUp:
                AutoBackupSheet(container: modelContext.container) {
                    sheet = nil
                    refreshState()
                }
            case .restore:
                RestoreSheet(coordinator: BackupCoordinator(container: modelContext.container)) { sheet = nil }
            case let .recoveryKey(key):
                RecoveryKeySheet(key: key) { sheet = nil }
            }
        }
    }

    private var footerText: String {
        let place = AutoBackupSettings.iCloudDriveFolder() == nil
            ? "a folder you choose"
            : "iCloud Drive or a folder you choose"
        return "Keeps one encrypted file for this Mac in \(place). It is encrypted here before it is saved, so the " +
            "folder's provider sees only scrambled bytes; without your passphrase or recovery key it cannot be read. " +
            "Your other Macs' files are never read or changed, and restoring stays up to you. Remove it on a Mac you " +
            "do not want backed up, such as a work laptop."
    }

    private var backupStatus: BackupStatus {
        BackupStatus(isEnabled: isConfigured, pausedAfterClear: paused)
    }

    private var chip: BackupChip {
        BackupChip(status: backupStatus, lastBackup: lastBackup, problem: problem)
    }

    private var backupSwitch: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle("Back up this Mac", isOn: Binding(
                get: { isConfigured },
                set: { on in
                    if on { show(.setUp) } else { confirmsTurningOff = true }
                }
            ))
            .accessibilityIdentifier(AccessibilityID.backupSwitch)
            Text(
                "Keeps one encrypted file of your clips, collections, snippets and settings. Restore it on any Mac. " +
                    "A backup never changes another Mac."
            )
            .pestoCaption()
        }
    }

    private var restoreRow: some View {
        Button("Restore from Backup\u{2026}") { show(.restore) }
            .accessibilityIdentifier(AccessibilityID.restoreBackupButton)
    }

    private var recoveryKeyRow: some View {
        Button("Show Recovery Key\u{2026}") { Task { await showRecoveryKey() } }
            .disabled(appState.authenticationAvailability == .unavailable)
            .accessibilityIdentifier(AccessibilityID.showRecoveryKeyButton)
    }

    @ViewBuilder
    private var configured: some View {
        if let folder = settings.folder {
            LabeledContent("Where your copies live") {
                HStack {
                    Text(folder.lastPathComponent).pestoQuiet().lineLimit(1).truncationMode(.middle)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    Button("Change\u{2026}", action: changeFolder)
                        .disabled(working)
                        .accessibilityIdentifier(AccessibilityID.backupChangeFolderButton)
                }
            }
        }
        if let protection = settings.protection {
            LabeledContent("Protected by") {
                HStack {
                    Text(protection == .recoveryKey ? "Recovery key" : "Passphrase").pestoQuiet()
                    recoveryKeyRow
                }
            }
        } else {
            recoveryKeyRow
        }
        Toggle("Include clips with secrets", isOn: Binding(
            get: { includesSecrets },
            set: { on in Task { await setIncludesSecrets(on) } }
        ))
        .accessibilityIdentifier(AccessibilityID.backupIncludesSecretsToggle)
        Text(
            "Card numbers, keys and tokens. Left out unless you turn this on. Copies kept from a password manager " +
                "are never included."
        )
        .pestoCaption()
        Text("In your backup: clips with their pins, snippets, collections and this Mac\u{2019}s settings.")
            .pestoCaption()
        if settings.lastSkippedLarge > 0 {
            Text("\(settings.lastSkippedLarge) clips over 10 MB, such as large pictures, are left out.")
                .pestoCaption()
        }
    }

    private var nextText: String? {
        _ = now
        guard let next = AutoBackupHolder.service?.nextBackup else {
            return "Up to date: nothing has changed since the last backup."
        }
        return "Next backup around \(next.formatted(date: .omitted, time: .shortened))."
    }

    /// A key exists once any backup has been written (each one raises the sequence), or a backup is set up. Asking the
    /// Keychain instead would prompt for a password just for opening this pane on a build the item does not know.
    private static func storedKeyExists() -> Bool {
        AutoBackupSettings().isEnabled || AppDefaults.store.integer(forKey: BackupCoordinator.sequenceKey) > 0
    }

    private func refreshState() {
        paused = settings.pausedAfterClear
        isConfigured = settings.isEnabled
        automatic = settings.runsAutomatically
        includesSecrets = settings.includesSecrets
        problem = settings.problem
        lastBackup = settings.lastBackup
        hasRecoveryKey = Self.storedKeyExists()
    }

    private func setIncludesSecrets(_ on: Bool) async {
        guard await ProtectedAction.permitted(reason: "Change what your Pesto backup includes") else { return }
        settings.includesSecrets = on
        includesSecrets = on
        AutoBackupHolder.service?.noteChange()
    }

    private func show(_ which: ActiveSheet) {
        Task {
            guard await ProtectedAction.permitted(reason: "Set up, restore or run your Pesto backup") else { return }
            sheet = which
        }
    }

    private func showRecoveryKey() async {
        guard await HistoryLockPolicy.permitsSensitiveAction(
            using: UserAuthenticator.current, reason: "Show the recovery key for your Pesto backups",
            requireFresh: true
        ) else { return }
        guard let key = try? BackupKeyStore().existingKey() else { return }
        sheet = .recoveryKey(key.recoveryKey)
    }

    private func removeBackup() {
        AutoBackupHolder.service?.disable()
        settings.turnOff()
        refreshState()
        status = "Backup is off. The file stays in its folder; delete it in Finder if you no longer want it."
    }

    private func backUpNow(allowShrink: Bool = false) async {
        guard await ProtectedAction.permitted(reason: "Back up your clipboard history") else { return }
        working = true
        defer { working = false }
        let service = AutoBackupHolder.service ?? AutoBackupService(container: modelContext.container)
        AutoBackupHolder.service = service
        await report(service.backUpNow(allowShrink: allowShrink), written: "Backed up.")
        refreshState()
    }

    private func report(_ outcome: AutoBackupService.Outcome, written: String) {
        switch outcome {
        case .written:
            status = written
            pulse += 1
        case .needsSetup: status = "Turn the backup off and set it up again."
        case .folderUnavailable:
            status = "The folder is not available. Is the drive or iCloud Drive connected? You can choose another."
        case .failed: status = "The backup could not be written."
        case let .refused(refusal):
            status = BackupMessages.text(for: refusal)
            if refusal.needsConfirmation { confirmsReplacement = true }
            if case let .unreadableClips(count) = refusal { unreadableCount = count }
        }
    }

    private func changeFolder() {
        Task {
            guard await ProtectedAction.permitted(reason: "Move your Pesto backup to another folder") else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.message = "Choose the folder for the backup file"
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            working = true
            defer { working = false }
            let service = AutoBackupHolder.service ?? AutoBackupService(container: modelContext.container)
            AutoBackupHolder.service = service
            await report(
                service.changeFolder(to: folder),
                written: "Backup moved. The old file stays in its folder; delete it in Finder if you no longer want it."
            )
            refreshState()
        }
    }

    private func deleteUnreadableClips() async {
        guard let service = AutoBackupHolder.service else { return }
        let removed = await service.deleteUnreadableClips()
        unreadableCount = 0
        status = String(localized: "Deleted \(removed) clips that could not be opened.")
        await backUpNow()
    }
}

private extension AutoBackupRefusal {
    var needsConfirmation: Bool {
        switch self {
        case .muchSmaller, .keptAfterClear: true
        case .storeNotOnDisk, .unreadableClips, .anotherKeyInFolder: false
        }
    }
}

enum BackupMessages {
    static func text(for refusal: AutoBackupRefusal) -> String {
        switch refusal {
        case .storeNotOnDisk:
            "Pesto could not open your saved history, so this session is not saved. The backup was left as it is."
        case let .unreadableClips(count):
            String(localized: "\(count) clips cannot be opened, so the backup was left as it is.")
        case .muchSmaller:
            "Your history is much smaller than the last backup, so the backup was left as it is."
        case .keptAfterClear:
            "You cleared your history and chose to keep the backup, so it was left as it is."
        case .anotherKeyInFolder:
            "The folder holds a backup this Mac\u{2019}s key does not open, so it was left as it is. " +
                "Restore from it, choose another folder, or delete the file."
        }
    }

    static func text(for error: any Error) -> String {
        if error as? AutoBackupError == .backupAlreadyInFolder {
            return "That folder already holds a Pesto backup this Mac cannot open. " +
                "Restore from it first, choose another folder, or delete the file."
        }
        return switch error as? BackupError {
        case .wrongCredential: "That passphrase or recovery key does not open this backup."
        case .notABackup: "That file is not a Pesto backup."
        case .unsupportedVersion: "This backup was made by a newer Pesto. Update Pesto to open it."
        case .corrupted: "This file is damaged or has been changed, so Pesto will not use it."
        case .malformedRecoveryKey: "That recovery key is not valid. Check it for a typo."
        case nil: "Couldn’t open the backup. Try another file or try again."
        }
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
