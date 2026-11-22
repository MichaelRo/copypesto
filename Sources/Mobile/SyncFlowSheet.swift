// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Whichever step of turning sync on or joining the controller is at, one sheet per step, as on the Mac.
struct SyncFlowSheet: View {
    let sync: MobileSync
    @AppStorage(Setting.syncIncludesSecrets) private var includesSecrets: Bool
    @State private var recoveryKey = ""
    @State private var copiedRecoveryKey = false
    @State private var confirmsReset = false

    private var device: SyncDeviceKind {
        sync.deviceKind
    }

    private var mode: SyncKeyMode {
        sync.keyMode ?? .thisDevice
    }

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(sync.flow.isRecoveryKey)
        .confirmationDialog("Reset Sync?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Sync", role: .destructive) { Task { await sync.reset() } }
        } message: {
            Text(verbatim: SyncCopy.resetMessage(mode, device: device))
        }
    }

    private var title: String {
        switch sync.flow {
        case .idle, .setUp: String(localized: "Turn On Sync")
        case .joinOffer: String(localized: "Join Your Sync")
        case .iCloudKeychainOff: String(localized: "iCloud Keychain Is Off")
        case .needsKey: String(localized: "This \(device.name) Needs the Key")
        case .pairing: String(localized: "Check These Words")
        case .enterRecoveryKey: String(localized: "Recovery Key")
        case .recoveryKey: String(localized: "Your Recovery Key")
        case .failed: String(localized: "Sync Could Not Continue")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sync.flow {
        case .idle: EmptyView()
        case .setUp: setUp
        case let .joinOffer(here, synced): joinOffer(here: here, synced: synced)
        case .iCloudKeychainOff:
            Section {
                Text(verbatim: SyncCopy.keychainOffLead(device))
            } footer: {
                Text("Turn it on in the Settings app, or join with a recovery key instead.")
            }
            Section { Button("Enter Recovery Key\u{2026}") { sync.beginRecoveryKeyEntry() } }
        case .needsKey:
            Section { Text(verbatim: SyncCopy.needsKeyLead(mode, device: device)) }
            Section {
                Button("Ask Another Device\u{2026}") { sync.askAnotherDevice() }
                Button("Enter Recovery Key\u{2026}") { sync.beginRecoveryKeyEntry() }
            } footer: {
                Text("Another device shows a request, and you check that the words on both screens match.")
            }
            Section {
                Button("Reset Sync\u{2026}", role: .destructive) {
                    Task { if await sync.permitsProtectedAction() { confirmsReset = true } }
                }
            }
        case let .pairing(words, approver):
            Section {
                Text("\(approver) shows a request from this \(device.name). Confirm both screens show the same words.")
                SyncWordsGrid(words: words)
            }
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for the other device to allow it\u{2026}").foregroundStyle(.secondary)
                }
            }
        case .enterRecoveryKey:
            Section {
                TextField("Recovery key", text: $recoveryKey, axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(MobileAccessibilityID.syncRecoveryKeyField)
            } footer: {
                Text("The key shown when sync was turned on, or after Reset Sync.")
            }
            Section {
                Button("Reset Sync\u{2026}", role: .destructive) {
                    Task { if await sync.permitsProtectedAction() { confirmsReset = true } }
                }
            }
        case let .recoveryKey(key):
            Section {
                Text(verbatim: SyncCopy.recoveryKeyLead(mode, device: device))
            }
            Section {
                Text(key)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier(MobileAccessibilityID.syncRecoveryKey)
                Button {
                    MobileClipboard.write(.text(key), protected: true)
                    copiedRecoveryKey = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedRecoveryKey = false
                    }
                } label: {
                    Label(
                        copiedRecoveryKey ? "Copied" : "Copy",
                        systemImage: copiedRecoveryKey ? "checkmark" : "doc.on.doc"
                    )
                }
            } footer: {
                Text("A copy stays on this device and leaves the clipboard after two minutes.")
            }
        case let .failed(message):
            Section { Text(message) }
        }
    }

    @ViewBuilder
    private var setUp: some View {
        Section {
            Text(verbatim: SyncCopy.intro(device))
        }
        Section {
            if let folder = sync.folderName {
                Text("Encrypted files go to **\(folder)**.")
            }
            Text(verbatim: SyncCopy.keyLine(mode, device: device))
            Text("Clips with secrets stay on this \(device.name) unless you choose.")
            Text("Deleting a clip on one device deletes it on all. Sync is not a backup.")
            Text("iCloud can see how many devices you have, file sizes and when files change, not your clips.")
        }
        .font(.subheadline)
        Section {
            Toggle("Also sync clips with secrets", isOn: $includesSecrets)
        }
    }

    private func joinOffer(here: Int, synced: Int) -> some View {
        Section {
            LabeledContent("Clips on this \(device.name)", value: here.formatted())
            LabeledContent("Clips already synced", value: synced.formatted())
        } footer: {
            Text("Nothing is deleted. Clips are merged both ways, and Pesto stays usable while it runs.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch sync.flow {
        case .setUp:
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { sync.cancelFlow() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Turn On") { Task { await sync.turnOn() } }
            }
        case .joinOffer:
            ToolbarItem(placement: .cancellationAction) { Button("Not Now") { sync.cancelFlow() } }
            ToolbarItem(placement: .confirmationAction) { Button("Join and Merge") { sync.confirmJoin() } }
        case .enterRecoveryKey:
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { sync.cancelFlow() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") { Task { await sync.useRecoveryKey(recoveryKey) } }
                    .disabled(recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        case .recoveryKey, .failed:
            ToolbarItem(placement: .confirmationAction) { Button("Done") { sync.cancelFlow() } }
        case .idle, .iCloudKeychainOff, .needsKey, .pairing:
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { sync.cancelFlow() } }
        }
    }
}

private extension SyncFlow {
    var isRecoveryKey: Bool {
        if case .recoveryKey = self { return true }
        return false
    }
}

/// The eight pairing words in two rows of four, numbered, as both screens show them.
struct SyncWordsGrid: View {
    let words: [String]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(Array(stride(from: 0, to: words.count, by: 4)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + 4, words.count), id: \.self) { index in
                        Text(words[index]).font(.body.monospaced().weight(.semibold))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
