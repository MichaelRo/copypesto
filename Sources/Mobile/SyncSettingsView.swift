// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UniformTypeIdentifiers

/// Sync on this iPhone or iPad: the real state, the folder, the key, and Reset Sync as the one repair. There is no
/// list of devices here or anywhere (ADR 0018).
struct SyncSettingsView: View {
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        Group {
            if let sync = appState.sync {
                SyncSettingsForm(sync: sync)
            } else {
                Form {
                    Text("Sync needs your history, which did not open.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sync")
    }
}

private struct SyncSettingsForm: View {
    let sync: MobileSync
    @AppStorage(Setting.syncIncludesSecrets) private var includesSecrets: Bool
    @State private var picksFolder = false
    @State private var confirmsReset = false
    @State private var confirmsLeave = false
    @State private var isSyncingNow = false

    private var device: SyncDeviceKind {
        sync.deviceKind
    }

    var body: some View {
        Form {
            Section {
                SyncStatusRow(status: sync.status)
                if sync.isEnabled {
                    Button {
                        Task {
                            isSyncingNow = true
                            await sync.syncNow()
                            isSyncingNow = false
                        }
                    } label: {
                        HStack {
                            Text("Sync Now")
                            Spacer()
                            if isSyncingNow { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isSyncingNow)
                }
                if sync.status.needsFolder {
                    Button("Choose Folder Again\u{2026}") { picksFolder = true }
                        .accessibilityIdentifier(MobileAccessibilityID.syncChooseFolderButton)
                }
            } footer: {
                if !sync.isEnabled { Text(verbatim: SyncCopy.intro(device)) }
            }
            if sync.isEnabled { enabledSections } else { offSections }
        }
        .sheet(isPresented: $picksFolder) {
            SyncFolderPicker(
                initialDirectory: BookmarkedSyncFolder.suggestedPickerDirectory(),
                onPicked: { url in
                    picksFolder = false
                    sync.useFolder(url)
                },
                onCancel: { picksFolder = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(get: { sync.flow != .idle }, set: { if !$0 { sync.cancelFlow() } })) {
            SyncFlowSheet(sync: sync)
        }
        .sheet(isPresented: Binding(
            get: { sync.pendingJoin != nil && sync.flow == .idle }, set: { _ in }
        )) {
            if let pending = sync.pendingJoin { SyncApproveView(sync: sync, pending: pending) }
        }
        .confirmationDialog("Reset Sync?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Sync", role: .destructive) { Task { await sync.reset() } }
        } message: {
            Text(verbatim: SyncCopy.resetMessage(sync.keyMode ?? .thisDevice, device: device))
        }
        .confirmationDialog(
            String(localized: "Leave Sync on \(device.thisDevice)?"), isPresented: $confirmsLeave,
            titleVisibility: .visible
        ) {
            Button("Leave Sync", role: .destructive) { sync.leave() }
        } message: {
            Text(
                "This \(device.name) stops syncing and removes its own files from the folder. Your other devices " +
                    "keep everything. Clips already here stay."
            )
        }
        .task(id: sync.isEnabled) {
            while !Task.isCancelled {
                sync.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var offSections: some View {
        Section {
            Button("Turn On Sync\u{2026}") {
                if sync.canBeginSetUp {
                    sync.beginSetUp()
                } else {
                    picksFolder = true
                }
            }
            .accessibilityIdentifier(MobileAccessibilityID.syncTurnOnButton)
            if let name = sync.folderName {
                LabeledContent("Folder", value: name)
                Button("Choose Another Folder\u{2026}") { picksFolder = true }
            }
        } footer: {
            Text(
                "Choose your sync folder (such as iCloud Drive). Clips with secrets stay on this \(device.name) " +
                    "unless you choose."
            )
        }
    }

    @ViewBuilder
    private var enabledSections: some View {
        Section {
            if let name = sync.folderName { LabeledContent("Folder", value: name) }
            Toggle("Also sync clips with secrets", isOn: Binding(
                get: { includesSecrets }, set: { on in Task { await sync.setIncludesSecrets(on) } }
            ))
        }
        Section {
            LabeledContent(
                "Sync key",
                value: sync.keyMode == .iCloudKeychain ? String(localized: "iCloud Keychain") : device.name
            )
            Button("Show Recovery Key\u{2026}") { Task { await sync.showRecoveryKey() } }
        } footer: {
            Text(verbatim: SyncCopy.keyLine(sync.keyMode ?? .thisDevice, device: device))
        }
        Section {
            Button("Turn Off Sync") { sync.turnOff() }
            Button("Choose Another Folder\u{2026}") { picksFolder = true }
            Button("Reset Sync\u{2026}", role: .destructive) {
                Task { if await sync.permitsProtectedAction() { confirmsReset = true } }
            }
            Button("Leave Sync\u{2026}", role: .destructive) {
                Task { if await sync.permitsProtectedAction() { confirmsLeave = true } }
            }
        } footer: {
            Text("Turning sync off keeps this device in your sync, so turning it on again needs nothing.")
        }
    }
}

private struct SyncStatusRow: View {
    let status: MobileSyncStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).font(.headline)
                Text(status.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(MobileAccessibilityID.syncStatus)
    }

    private var color: Color {
        switch status.tone {
        case .good: .statusGood
        case .neutral: .secondary
        case .attention: .statusWarning
        case .problem: .statusBad
        }
    }
}
