// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI

/// The one place a backup is set up: where the file goes, how it is protected, and whether it keeps itself up to date.
struct AutoBackupSheet: View {
    private enum Protection: String, CaseIterable, Identifiable {
        case recoveryKey = "Recovery key only"
        case passphrase = "Passphrase"

        var id: Self {
            self
        }
    }

    private enum Place: String, CaseIterable, Identifiable {
        case iCloud = "iCloud Drive"
        case other = "Another folder"

        var id: Self {
            self
        }
    }

    let container: ModelContainer
    let onClose: () -> Void
    @State private var protection = Protection.recoveryKey
    @State private var passphrase = ""
    @State private var repeated = ""
    @State private var place: Place
    @State private var otherFolder: URL?
    @State private var includeSecrets = false
    @State private var automatic = true
    @State private var working = false
    @State private var recoveryKey: String?
    @State private var recoveryStored = false
    @State private var message: String?
    private let iCloudFolder: URL?

    /// `iCloudFolder` is where iCloud Drive keeps the file; nil when this Mac has none (or in a test run).
    init(
        container: ModelContainer,
        iCloudFolder: URL? = AutoBackupSheet.suggestedFolder,
        onClose: @escaping () -> Void
    ) {
        self.container = container
        self.onClose = onClose
        self.iCloudFolder = iCloudFolder
        _place = State(initialValue: iCloudFolder == nil ? .other : .iCloud)
    }

    private var folder: URL? {
        place == .iCloud ? iCloudFolder : otherFolder
    }

    private var strength: PassphraseStrength {
        PassphraseStrength.evaluate(passphrase)
    }

    private var protectionIsReady: Bool {
        protection == .recoveryKey || (strength.isAcceptable && passphrase == repeated)
    }

    private var canTurnOn: Bool {
        protectionIsReady && folder != nil && !working
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set Up Backup").font(.title3.weight(.semibold))
            if let recoveryKey {
                RecoveryKeyNotice(key: recoveryKey, stored: $recoveryStored)
                HStack {
                    Spacer()
                    Button("Done", action: onClose)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!recoveryStored)
                }
            } else {
                form
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            placeChooser
            Picker("Protect it with", selection: $protection) {
                ForEach(Protection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AccessibilityID.settingsChoice("autoBackup", "protection"))
            if protection == .passphrase {
                SecureField("Passphrase", text: $passphrase)
                    .accessibilityIdentifier(AccessibilityID.backupPassphraseField)
                SecureField("Repeat passphrase", text: $repeated)
                    .accessibilityIdentifier(AccessibilityID.backupRepeatField)
                Text(strengthText).pestoCaption()
            } else {
                Text(
                    "Pesto makes a long random recovery key and shows it next. Keep it in your password manager: it " +
                        "is the only thing that opens the file, and you can show it again here later."
                )
                .pestoCaption()
            }
            Toggle("Include clips that hold secrets (card numbers, keys)", isOn: $includeSecrets)
            Text(
                "Copies kept from a password manager are never included. The previous copy beside the file is one " +
                    "backup behind, so a clip you delete stays in it until the next backup."
            )
            .pestoCaption()
            Toggle("Keep it up to date automatically", isOn: $automatic)
            Text(
                "The file is encrypted on this Mac before it is saved, so the folder's provider sees only scrambled " +
                    "bytes. Pesto remembers how to write it, so it does not ask again; you need the " +
                    "\(protection == .passphrase ? "passphrase or the recovery key" : "recovery key") only to restore."
            )
            .pestoCaption()
            if let message { Text(message).font(.caption).foregroundStyle(Color.statusWarning) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onClose).keyboardShortcut(.cancelAction)
                Button("Set Up") { Task { await turnOn() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canTurnOn)
                    .accessibilityIdentifier(AccessibilityID.backupSaveButton)
            }
        }
    }

    @ViewBuilder
    private var placeChooser: some View {
        if iCloudFolder != nil {
            Picker("Keep the file in", selection: $place) {
                ForEach(Place.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AccessibilityID.settingsChoice("autoBackup", "place"))
        }
        if place == .iCloud {
            Text("A folder named Pesto in your iCloud Drive.").pestoCaption()
        } else {
            HStack {
                Button("Choose Folder\u{2026}", action: chooseFolder)
                Text(otherFolder?.path ?? "No folder chosen").pestoQuiet().lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var strengthText: String {
        if !passphrase.isEmpty, passphrase != repeated, repeated.count >= passphrase.count {
            return "The two passphrases are different."
        }
        return switch strength {
        case .tooShort: "Use at least 10 characters, or a few words."
        case .weak: "Too easy to guess. Try a few unrelated words."
        case .fair: "Fair. A few more words would make it strong."
        case .strong: "Strong."
        }
    }

    /// A test run never looks at the real iCloud Drive.
    private static var suggestedFolder: URL? {
        RuntimeConfiguration.current.mode == .normal ? AutoBackupSettings.iCloudDriveFolder() : nil
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder for the backup file"
        if panel.runModal() == .OK { otherFolder = panel.url }
    }

    private func turnOn() async {
        guard let folder else { return }
        working = true
        defer { working = false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let service = AutoBackupHolder.service ?? AutoBackupService(container: container)
            AutoBackupHolder.service = service
            let result = try await service.enable(
                passphrase: protection == .passphrase ? passphrase : nil,
                folder: folder,
                includeSensitive: includeSecrets,
                automatic: automatic
            )
            if case .written = result.outcome {
                if let key = result.recoveryKey { recoveryKey = key } else { onClose() }
            } else {
                service.disable()
                message = "The first backup could not be written to that folder. Choose another one."
            }
        } catch {
            message = "Couldn’t turn it on. \(BackupMessages.text(for: error))"
        }
    }
}
